import CoreBluetooth
import Foundation

struct DiscoveredT50: Identifiable {
    var id: UUID { identifier }
    var identifier: UUID
    var name: String
    fileprivate var peripheral: CBPeripheral
}

@MainActor
final class T50BluetoothPrinter: NSObject, ObservableObject {
    @Published private(set) var discovered: [DiscoveredT50] = []
    @Published private(set) var statusText = "Looking for a T50M…"
    @Published private(set) var connectedName: String?
    @Published private(set) var connectedIdentifier: UUID?
    @Published private(set) var isBusy = false

    private var central: CBCentralManager?
    private var connected: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var rx = Data()
    private var frames: [Data] = []
    private var responseWait: ResponseWait?
    private var writeWait: CheckedContinuation<Void, Error>?
    private var connectWait: CheckedContinuation<Void, Error>?
    private var readyWait: CheckedContinuation<Void, Error>?
    private var serviceQueue: [CBService] = []
    private var foundChannels: [(service: CBUUID, write: CBCharacteristic, notify: CBCharacteristic?)] = []
    /// First link often drops when notifications are enabled. The retry holds the write channel only.
    private var retryWithoutNotify = false

    private let rememberedKey = "gardens.t50.peripheral"

    func start() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else if central?.state == .poweredOn {
            scan()
        }
    }

    func stop() {
        central?.stopScan()
    }

    func connect(_ printer: DiscoveredT50) {
        guard let central else { return }
        isBusy = true
        retryWithoutNotify = false
        statusText = "Connecting to \(printer.name)…"
        central.stopScan()
        if let connected, connected.identifier != printer.identifier {
            central.cancelPeripheralConnection(connected)
            self.connected = nil
            writeCharacteristic = nil
            notifyCharacteristic = nil
            connectedName = nil
            connectedIdentifier = nil
        }
        connected = printer.peripheral
        printer.peripheral.delegate = self
        central.connect(printer.peripheral, options: nil)
    }

    func printJobs(_ jobs: [PlantLabelJob]) async throws {
        guard connected != nil, writeCharacteristic != nil, notifyCharacteristic != nil else {
            throw T50PrinterError.notConnected
        }
        isBusy = true
        defer { isBusy = false }
        for (index, job) in jobs.enumerated() {
            statusText = jobs.count == 1
                ? "Printing \(job.title)…"
                : "Printing \(index + 1) of \(jobs.count)…"
            try await printOne(job)
        }
        statusText = jobs.count == 1 ? "Label sent." : "\(jobs.count) labels sent."
    }

    private func scan() {
        central?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        statusText = "Looking for a T50M…"
        if let raw = UserDefaults.standard.string(forKey: rememberedKey), let id = UUID(uuidString: raw) {
            let known = central?.retrievePeripherals(withIdentifiers: [id]) ?? []
            for peripheral in known {
                remember(peripheral)
            }
        }
    }

    private func remember(_ peripheral: CBPeripheral) {
        let name = peripheral.name ?? "T50M"
        guard Self.isPrinter(name: name, services: nil) || peripheral.name == nil else { return }
        let item = DiscoveredT50(identifier: peripheral.identifier, name: peripheral.name ?? "Label printer", peripheral: peripheral)
        if let index = discovered.firstIndex(where: { $0.identifier == item.identifier }) {
            discovered[index] = item
        } else {
            discovered.append(item)
        }
    }

    private static func isPrinter(name: String?, services: [CBUUID]?) -> Bool {
        let upper = (name ?? "").uppercased()
        if upper.contains("T50") || upper.contains("SUPVAN") || upper.contains("KATA") || upper.hasPrefix("T0117") {
            return true
        }
        if let first = upper.first, "TGD".contains(first), upper.dropFirst().prefix(2).allSatisfy(\.isNumber) {
            return true
        }
        for uuid in services ?? [] {
            let token = uuid.uuidString.uppercased()
            if token.hasPrefix("FEE7") || token.hasPrefix("FF00") || token.contains("E0FF") {
                return true
            }
        }
        return false
    }

    private func printOne(_ job: PlantLabelJob) async throws {
        let raster = try SupvanLabel.raster(title: job.title, subtitle: job.subtitle, qrPayload: job.qrPayload)
        let buffers = try SupvanLabel.printBuffers(raster: raster.data, columns: raster.columns)
        let blocks = try SupvanLabel.compressGrouped(buffers)

        _ = try await command(0x12, blockSize: 0, blockCount: 0)
        try await waitStatus(timeout: 4) { !$0.deviceBusy }
        _ = try await command(0x13, blockSize: 0, blockCount: 0)
        try await waitStatus(timeout: 4) { $0.printing }

        for block in blocks {
            try await waitStatus(timeout: 6) { !$0.bufFull }
            let frames = SupvanLabel.dataFrames(compressed: block.data)
            guard frames.count <= Int(UInt16.max) else { throw T50PrinterError.compressedTooLarge }
            _ = try await command(0x5C, blockSize: 512, blockCount: UInt16(frames.count))
            for frame in frames {
                try await write(frame)
            }
            try await Task.sleep(nanoseconds: 20_000_000)
            let length = UInt16(min(block.data.count, Int(UInt16.max)))
            _ = try await command(0x10, blockSize: length, blockCount: block.speed)
        }
        try await waitStatus(timeout: 8) { !$0.printing }
    }

    private func waitStatus(timeout: TimeInterval, _ ready: (SupvanStatus) -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let frame = try await command(0x11, blockSize: 0, blockCount: 0)
            if let status = SupvanLabel.status(from: frame) {
                if status.labelMissing || status.coverOpen {
                    throw T50PrinterError.printerRejected
                }
                if ready(status) { return }
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw T50PrinterError.timeout
    }

    private func command(_ cmd: UInt8, blockSize: UInt16, blockCount: UInt16) async throws -> Data {
        let packet = SupvanLabel.command(cmd, blockSize: blockSize, blockCount: blockCount)
        try await write(packet)
        return try await waitFor(cmd: cmd, timeout: 4)
    }

    private func write(_ data: Data) async throws {
        guard let peripheral = connected, let characteristic = writeCharacteristic else {
            throw T50PrinterError.notConnected
        }
        let supportsResponse = characteristic.properties.contains(.write)
        let writeType: CBCharacteristicWriteType = supportsResponse ? .withResponse : .withoutResponse
        let maxLength = max(20, peripheral.maximumWriteValueLength(for: writeType))
        let chunkSize = min(128, maxLength)
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            let piece = data.subdata(in: offset..<end)
            if supportsResponse {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    self.writeWait = cont
                    peripheral.writeValue(piece, for: characteristic, type: .withResponse)
                }
            } else {
                peripheral.writeValue(piece, for: characteristic, type: .withoutResponse)
            }
            offset = end
            if offset < data.count {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }
    }

    private func waitFor(cmd: UInt8, timeout: TimeInterval) async throws -> Data {
        if let index = frames.firstIndex(where: { $0.count > 7 && $0[7] == cmd }) {
            return frames.remove(at: index)
        }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            let wait = ResponseWait(cmd: cmd, continuation: cont)
            responseWait = wait
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard self.responseWait === wait else { return }
                self.responseWait = nil
                wait.resume(throwing: T50PrinterError.timeout)
            }
        }
    }

    private func absorb(_ chunk: Data) {
        rx.append(chunk)
        while rx.count >= 4 {
            let bytes = [UInt8](rx.prefix(4))
            guard bytes[0] == 0x7E, bytes[1] == 0x5A else {
                rx.removeFirst()
                continue
            }
            let length = Int(bytes[2]) | (Int(bytes[3]) << 8)
            let total = length + 4
            guard total > 4, rx.count >= total else { return }
            let frame = rx.prefix(total)
            rx.removeFirst(total)
            deliver(Data(frame))
        }
    }

    private func deliver(_ frame: Data) {
        if let wait = responseWait, frame.count > 7, frame[7] == wait.cmd {
            responseWait = nil
            wait.resume(returning: frame)
        } else {
            frames.append(frame)
        }
    }

    private func finishConnect(error: Error?) {
        isBusy = false
        serviceQueue = []
        if let error {
            statusText = error.localizedDescription
            connectWait?.resume(throwing: error)
            connectWait = nil
        }
    }

    private func openNextService(on peripheral: CBPeripheral) {
        guard let service = serviceQueue.first else {
            subscribeToBestChannel(on: peripheral)
            return
        }
        serviceQueue.removeFirst()
        peripheral.discoverCharacteristics(nil, for: service)
    }

    private func subscribeToBestChannel(on peripheral: CBPeripheral) {
        guard let best = foundChannels.first(where: { Self.matches($0.service) }) ?? foundChannels.first else {
            statusText = "Connected to \(connectedName ?? "T50M"), but it has no print channel yet."
            isBusy = false
            return
        }
        writeCharacteristic = best.write
        let notify = best.notify
        let canNotify = notify.map { $0.properties.contains(.notify) || $0.properties.contains(.indicate) } ?? false
        if !retryWithoutNotify, let notify, canNotify {
            notifyCharacteristic = notify
            peripheral.setNotifyValue(true, for: notify)
        } else {
            notifyCharacteristic = best.write
            markConnected()
        }
    }
}

private final class ResponseWait {
    let cmd: UInt8
    private var continuation: CheckedContinuation<Data, Error>?
    private var finished = false

    init(cmd: UInt8, continuation: CheckedContinuation<Data, Error>) {
        self.cmd = cmd
        self.continuation = continuation
    }

    func resume(returning data: Data) {
        guard !finished else { return }
        finished = true
        continuation?.resume(returning: data)
        continuation = nil
    }

    func resume(throwing error: Error) {
        guard !finished else { return }
        finished = true
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

extension T50BluetoothPrinter: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                self.scan()
            case .unauthorized:
                self.statusText = T50PrinterError.bluetoothDenied.localizedDescription
            case .poweredOff:
                self.statusText = T50PrinterError.bluetoothOff.localizedDescription
            default:
                self.statusText = "Waiting for Bluetooth…"
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertised = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]
        let name = advertised ?? peripheral.name ?? "Unnamed device"
        Task { @MainActor in
            guard Self.isPrinter(name: name, services: services) else { return }
            let item = DiscoveredT50(identifier: peripheral.identifier, name: name, peripheral: peripheral)
            if let index = self.discovered.firstIndex(where: { $0.identifier == item.identifier }) {
                self.discovered[index] = item
            } else {
                self.discovered.append(item)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            peripheral.delegate = self
            self.connected = peripheral
            self.connectedName = peripheral.name ?? self.connectedName ?? "T50M"
            self.connectedIdentifier = peripheral.identifier
            UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: self.rememberedKey)
            self.statusText = "Connected to \(self.connectedName ?? "T50M"). Checking the print channel…"
            self.foundChannels = []
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.finishConnect(error: error ?? T50PrinterError.timeout)
            self.connected = nil
            self.connectedName = nil
            self.connectedIdentifier = nil
            let message = (error ?? T50PrinterError.timeout).localizedDescription
            self.scan()
            self.statusText = message
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            guard self.connected?.identifier == peripheral.identifier || self.connectedIdentifier == peripheral.identifier else { return }
            self.writeCharacteristic = nil
            self.notifyCharacteristic = nil
            self.serviceQueue = []
            let name = self.connectedName ?? peripheral.name ?? "T50M"
            if !self.retryWithoutNotify {
                self.retryWithoutNotify = true
                self.connected = peripheral
                self.connectedName = name
                self.isBusy = true
                self.statusText = "Printer dropped the link. Holding \(name)…"
                self.central?.connect(peripheral, options: nil)
                return
            }
            let reason = error?.localizedDescription
            self.connected = nil
            self.connectedName = nil
            self.connectedIdentifier = nil
            self.isBusy = false
            self.retryWithoutNotify = false
            let message = reason.map { "Printer disconnected. \($0)" }
                ?? "Printer disconnected. Quit Katasymbol if it is open, then tap the T50M again."
            self.scan()
            self.statusText = message
        }
    }
}

extension T50BluetoothPrinter: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error {
                self.finishConnect(error: error)
                return
            }
            let services = peripheral.services ?? []
            let preferred = services.filter { Self.matches($0.uuid) }
            let rest = services.filter { !Self.matches($0.uuid) }
            self.foundChannels = []
            self.serviceQueue = preferred + rest
            self.openNextService(on: peripheral)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            if let error {
                self.statusText = error.localizedDescription
                self.openNextService(on: peripheral)
                return
            }
            let chars = service.characteristics ?? []
            let pair = Self.writeAndNotify(in: service.uuid, characteristics: chars)
            if let write = pair.write {
                self.foundChannels.append((service.uuid, write, pair.notify))
            }
            self.openNextService(on: peripheral)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error {
                if self.writeCharacteristic != nil {
                    self.markConnected()
                } else {
                    self.finishConnect(error: error)
                }
                return
            }
            self.markConnected()
        }
    }

    private func markConnected() {
        isBusy = false
        statusText = "Connected to \(connectedName ?? "T50M")."
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let value = characteristic.value ?? Data()
        Task { @MainActor in
            if error == nil {
                self.absorb(value)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            let wait = self.writeWait
            self.writeWait = nil
            if let error {
                wait?.resume(throwing: T50PrinterError.writeFailed(error.localizedDescription))
            } else {
                wait?.resume()
            }
        }
    }

    private static func matches(_ uuid: CBUUID) -> Bool {
        let token = uuid.uuidString.uppercased()
        return token.hasPrefix("FEE7") || token.hasPrefix("FF00") || token.contains("E0FF")
    }

    private static func writeAndNotify(in service: CBUUID, characteristics: [CBCharacteristic]) -> (write: CBCharacteristic?, notify: CBCharacteristic?) {
        func find(_ id: String) -> CBCharacteristic? {
            characteristics.first { $0.uuid.uuidString.uppercased().hasPrefix(id) }
        }
        let token = service.uuidString.uppercased()
        if token.hasPrefix("FEE7") {
            let shared = find("FEC1")
            return (shared, shared)
        }
        if token.contains("E0FF") {
            return (find("FFE9"), find("FFE1"))
        }
        if token.hasPrefix("FF00") {
            return (find("FF02"), find("FF01"))
        }
        let write = characteristics.first { $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse) }
        let notify = characteristics.first { $0.properties.contains(.notify) || $0.properties.contains(.indicate) }
        return (write, notify ?? write)
    }
}
