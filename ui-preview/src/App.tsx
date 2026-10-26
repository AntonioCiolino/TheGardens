import { useEffect, useMemo, useRef, useState } from "react";
import { QRCodeSVG } from "qrcode.react";
import "./App.css";

type CareProfile = {
  careInstructions: string;
  wateringCheckGuidance: string;
  healthCheckGuidance: string;
};

type CatalogType = {
  id: string;
  name: string;
  genus: string;
  care: CareProfile;
};

type Plant = {
  id: string;
  catalogId: string;
  name: string;
  genus: string;
  vendor: string;
  arrivedOn: string;
  photo: string;
  care: CareProfile;
  history: {
    kind: string;
    when: string;
    watering?: string;
    health?: string;
    notes: string;
  }[];
};

const CATALOG: CatalogType[] = [
  {
    id: "cat-snake",
    name: "Snake Plant",
    genus: "Dracaena",
    care: {
      careInstructions: "Bright indirect light. Allow soil to dry between waterings.",
      wateringCheckGuidance: "Probe 2 inches down — water only if dry.",
      healthCheckGuidance: "Yellow tips usually mean overwatering; soft leaves mean cold draft.",
    },
  },
  {
    id: "cat-fig",
    name: "Fiddle Leaf Fig",
    genus: "Ficus",
    care: {
      careInstructions: "Consistent bright light; wipe leaves monthly.",
      wateringCheckGuidance: "Lift the pot — water when it feels light.",
      healthCheckGuidance: "Brown spots can be inconsistent watering or low humidity.",
    },
  },
  {
    id: "cat-monstera",
    name: "Monstera Deliciosa",
    genus: "Monstera",
    care: {
      careInstructions: "Moss pole optional. Keep soil lightly moist in growing season.",
      wateringCheckGuidance: "Check top inch of soil every few days.",
      healthCheckGuidance: "Yellow oldest leaves are normal; check for pests under leaves.",
    },
  },
];

const SAMPLE: Plant[] = [
  {
    id: "7F3A9C21-4B8E-4D12-9A01-E2C45B678901",
    catalogId: "cat-snake",
    name: "Snake Plant",
    genus: "Dracaena",
    vendor: "Green Harbor Nursery",
    arrivedOn: "2026-10-22",
    photo:
      "https://images.unsplash.com/photo-1485955900006-10f4d324d411?w=800&q=80&auto=format&fit=crop",
    care: CATALOG[0].care,
    history: [
      { kind: "Watered", when: "Oct 23, 2026", notes: "Light soak" },
      { kind: "Health check", when: "Oct 22, 2026", notes: "Arrived healthy" },
    ],
  },
  {
    id: "A91C2D34-55E6-4F78-B901-C234567890AB",
    catalogId: "cat-fig",
    name: "Fiddle Leaf Fig",
    genus: "Ficus",
    vendor: "Westside Growers",
    arrivedOn: "2026-10-20",
    photo:
      "https://images.unsplash.com/photo-1459411552884-841db9b3cc2a?w=800&q=80&auto=format&fit=crop",
    care: CATALOG[1].care,
    history: [],
  },
  {
    id: "B02D3E45-66F7-4089-C012-D345678901BC",
    catalogId: "cat-monstera",
    name: "Monstera Deliciosa",
    genus: "Monstera",
    vendor: "Green Harbor Nursery",
    arrivedOn: "2026-10-18",
    photo:
      "https://images.unsplash.com/photo-1614594975525-e45190c55d0b?w=800&q=80&auto=format&fit=crop",
    care: CATALOG[2].care,
    history: [{ kind: "Repotted", when: "Oct 19, 2026", notes: "Into 8-inch nursery pot" }],
  },
];

type Screen = "list" | "add" | "detail" | "batch" | "scan" | "care" | "sync";

function compactQR(plant: Plant) {
  const name = encodeURIComponent(plant.name.slice(0, 80));
  return `gardens://plant/${plant.id}?n=${name}`;
}

function formatDate(iso: string) {
  return new Date(iso + "T12:00:00").toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

function newId() {
  return crypto.randomUUID().toUpperCase();
}

export default function App() {
  const [catalog, setCatalog] = useState<CatalogType[]>(CATALOG);
  const [plants, setPlants] = useState<Plant[]>(SAMPLE);
  const [screen, setScreen] = useState<Screen>("list");
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [batch, setBatch] = useState<Plant[]>([]);
  const [printNote, setPrintNote] = useState<string | null>(null);
  const [showSplash, setShowSplash] = useState(true);
  const [splashStyle, setSplashStyle] = useState<SplashStyle>(() => randomSplashStyle());
  const [splashKey, setSplashKey] = useState(0);
  const [iCloudConnected, setICloudConnected] = useState(false);
  const [syncStatus, setSyncStatus] = useState("On this phone only — connect iCloud under Sync");

  useEffect(() => {
    if (!showSplash) return;
    const t = window.setTimeout(() => setShowSplash(false), 3500);
    return () => window.clearTimeout(t);
  }, [showSplash, splashKey]);

  function replaySplash(next?: SplashStyle) {
    setSplashStyle(next ?? randomSplashStyle());
    setSplashKey((k) => k + 1);
    setShowSplash(true);
  }

  const selected = useMemo(
    () => plants.find((p) => p.id === selectedId) ?? null,
    [plants, selectedId]
  );

  return (
    <div className="stage">
      <header className="stage-copy">
        <p className="eyebrow">UI preview · not the Simulator</p>
        <h1>Gardens</h1>
        <p>
          Web stand-in for the iOS app. Sync simulates <strong>iCloud / CloudKit</strong>.
          Use <strong>Scan</strong> for QR → care log; <strong>Sync</strong> to connect iCloud and write a test plant.
        </p>
        <div className="splash-controls">
          {showSplash ? (
            <button type="button" className="skip-splash" onClick={() => setShowSplash(false)}>
              Skip splash
            </button>
          ) : (
            <button type="button" className="skip-splash" onClick={() => replaySplash()}>
              Replay random splash
            </button>
          )}
          <div className="splash-picks">
            {SPLASH_STYLES.map((s) => (
              <button key={s} type="button" className="skip-splash ghost" onClick={() => replaySplash(s)}>
                {s}
              </button>
            ))}
          </div>
        </div>
      </header>

      <div className="phone" aria-label="iPhone preview">
        <div className="notch" aria-hidden />
        <div className="status-bar">
          <span>9:41</span>
          <span className="status-icons">●●● ▮</span>
        </div>

        {showSplash && <SplashScreen style={splashStyle} />}

        {!showSplash && screen === "list" && (
          <ListScreen
            plants={plants}
            syncStatus={syncStatus}
            iCloudConnected={iCloudConnected}
            onAdd={() => setScreen("add")}
            onScan={() => setScreen("scan")}
            onSync={() => setScreen("sync")}
            onOpen={(id) => {
              setSelectedId(id);
              setScreen("detail");
            }}
            onDelete={(id) => {
              const next = plants.filter((p) => p.id !== id);
              const live = new Set(next.map((p) => p.catalogId));
              setPlants(next);
              setCatalog((cats) => cats.filter((c) => live.has(c.id)));
              if (selectedId === id) setSelectedId(null);
            }}
            onRefresh={() => {
              setSyncStatus(
                iCloudConnected
                  ? `iCloud sync · ${plants.length} plants · refreshed`
                  : `On this phone · ${plants.length} plants · refreshed`
              );
            }}
          />
        )}

        {!showSplash && screen === "sync" && (
          <SyncScreen
            iCloudConnected={iCloudConnected}
            syncStatus={syncStatus}
            hasSyncTest={plants.length > 0}
            onCancel={() => setScreen("list")}
            onConnect={() => {
              setICloudConnected(true);
              setSyncStatus(`iCloud sync · ${plants.length} plants`);
            }}
            onDisconnect={() => {
              setICloudConnected(false);
              setSyncStatus("On this phone only — connect iCloud under Sync");
            }}
            onWriteTest={() => {
              const id = newId();
              const today = new Date().toISOString().slice(0, 10);
              const stamp = new Date().toLocaleString();
              let catalogType = catalog.find(
                (c) => c.name === "Gardens Sync Test" && c.genus === "Testus"
              );
              let isNewCatalog = false;
              if (!catalogType) {
                catalogType = {
                  id: `cat-${id.slice(0, 8)}`,
                  name: "Gardens Sync Test",
                  genus: "Testus",
                  care: {
                    careInstructions: "Created by Sync → Write test record",
                    wateringCheckGuidance: "Ignore — smoke test",
                    healthCheckGuidance: "Ignore — smoke test",
                  },
                };
                isNewCatalog = true;
              }
              const plant: Plant = {
                id,
                catalogId: catalogType.id,
                name: catalogType.name,
                genus: catalogType.genus,
                vendor: "Setup Check",
                arrivedOn: today,
                photo:
                  "https://images.unsplash.com/photo-1485955900006-10f4d324d411?w=800&q=80&auto=format&fit=crop",
                care: catalogType.care,
                history: [
                  {
                    kind: "Note",
                    when: stamp,
                    notes: `CloudKit smoke test at ${stamp}`,
                  },
                ],
              };
              if (isNewCatalog) setCatalog((prev) => [...prev, catalogType!]);
              setPlants((prev) => [plant, ...prev]);
              setSyncStatus(
                iCloudConnected
                  ? `Test OK — plant ${id.slice(0, 8)}… (iCloud demo)`
                  : `Test OK — plant ${id.slice(0, 8)}… (this phone only)`
              );
              setPrintNote("Test plant written — check the list for Gardens Sync Test.");
              window.setTimeout(() => setPrintNote(null), 2800);
            }}
          />
        )}

        {!showSplash && screen === "scan" && (
          <ScanScreen
            plants={plants}
            onCancel={() => setScreen("list")}
            onMatched={(id) => {
              setSelectedId(id);
              setScreen("care");
            }}
          />
        )}

        {!showSplash && screen === "care" && selected && (
          <CareLogScreen
            plant={selected}
            onCancel={() => setScreen("detail")}
            onSave={(entry) => {
              setPlants((prev) =>
                prev.map((p) =>
                  p.id === selected.id ? { ...p, history: [entry, ...p.history] } : p
                )
              );
              setScreen("detail");
            }}
          />
        )}

        {!showSplash && screen === "add" && (
          <AddScreen
            catalog={catalog}
            plants={plants}
            onCancel={() => setScreen("list")}
            onSave={({ catalogType, created, isNewCatalog }) => {
              if (isNewCatalog) {
                setCatalog((prev) => [...prev, catalogType]);
              }
              setPlants((prev) => [...created, ...prev]);
              setBatch(created);
              setScreen("batch");
            }}
          />
        )}

        {!showSplash && screen === "batch" && (
          <BatchPrintScreen
            plants={batch}
            onDone={() => setScreen("list")}
            onPrintAll={() => {
              setPrintNote(
                `Print sheet opened for ${batch.length} unique label${batch.length === 1 ? "" : "s"}.`
              );
              window.setTimeout(() => setPrintNote(null), 2800);
            }}
          />
        )}

        {!showSplash && screen === "detail" && selected && (
          <DetailScreen
            plant={selected}
            onBack={() => setScreen("list")}
            onLogCare={() => setScreen("care")}
            onPhoto={(photo) => {
              setPlants((prev) =>
                prev.map((p) => (p.id === selected.id ? { ...p, photo } : p))
              );
            }}
            onPrint={() => {
              setPrintNote("Print sheet opened (preview) — AirPrint wiring in the iOS app.");
              window.setTimeout(() => setPrintNote(null), 2800);
            }}
          />
        )}

        {printNote && <div className="toast">{printNote}</div>}
      </div>
    </div>
  );
}

type SplashStyle = "centered" | "lifted" | "softGlow";

const SPLASH_STYLES: SplashStyle[] = ["centered", "lifted", "softGlow"];

function randomSplashStyle(): SplashStyle {
  return SPLASH_STYLES[Math.floor(Math.random() * SPLASH_STYLES.length)];
}

function SplashScreen({ style }: { style: SplashStyle }) {
  return (
    <div className={`splash splash-${style}`} role="img" aria-label="The Gardens splash">
      <div className="splash-orb" aria-hidden />
      <img
        className={`splash-logo-img splash-logo-${style}`}
        src="/brand-mark.png"
        alt="The Gardens"
      />
      <p className="splash-sub">Plant intake</p>
      <p className="splash-variant">Official logo · {style}</p>
    </div>
  );
}

function ListScreen({
  plants,
  syncStatus,
  iCloudConnected,
  onAdd,
  onScan,
  onSync,
  onOpen,
  onDelete,
  onRefresh,
}: {
  plants: Plant[];
  syncStatus: string;
  iCloudConnected: boolean;
  onAdd: () => void;
  onScan: () => void;
  onSync: () => void;
  onOpen: (id: string) => void;
  onDelete: (id: string) => void;
  onRefresh: () => void;
}) {
  const scroller = useRef<HTMLDivElement>(null);
  const pullStart = useRef<number | null>(null);
  const gesture = useRef<{ id: string; start: number; x: number } | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [swipe, setSwipe] = useState<{ id: string; x: number } | null>(null);
  const [confirmId, setConfirmId] = useState<string | null>(null);
  const dragged = useRef(false);
  const confirmPlant = plants.find((p) => p.id === confirmId);

  return (
    <div
      className="screen"
      ref={scroller}
      onPointerDown={(event) => {
        if ((scroller.current?.scrollTop ?? 0) <= 0) pullStart.current = event.clientY;
      }}
      onPointerUp={(event) => {
        if (pullStart.current != null && event.clientY - pullStart.current > 72) {
          setRefreshing(true);
          onRefresh();
          window.setTimeout(() => setRefreshing(false), 700);
        }
        pullStart.current = null;
      }}
    >
      <div className="nav">
        <div className="nav-leading">
          <button className="text-btn" onClick={onScan} aria-label="Scan plant">
            ⌁ Scan
          </button>
          <button className="text-btn" onClick={onSync} aria-label="Team sync">
            {iCloudConnected ? "☁ Synced" : "☁ Sync"}
          </button>
        </div>
        <h2>Gardens</h2>
        <button className="icon-btn" onClick={onAdd} aria-label="Add plant">
          +
        </button>
      </div>
      {refreshing && <p className="pull-note">Refreshing inventory…</p>}
      {plants.length === 0 ? (
        <div className="empty">
          <div className="empty-glyph">🌿</div>
          <h3>No plants yet</h3>
          <p>
            {iCloudConnected
              ? "Log an arrival — one plant or a whole carton."
              : "Connect iCloud under Sync to share, or add a plant on this phone."}
          </p>
        </div>
      ) : (
        <ul className="plant-list">
          {plants.map((p) => (
            <li key={p.id} className="plant-swipe">
              <span className="swipe-delete" aria-hidden>
                Delete
              </span>
              <button
                className="plant-row"
                style={{ transform: `translateX(${swipe?.id === p.id ? swipe.x : 0}px)` }}
                onPointerDown={(event) => {
                  dragged.current = false;
                  gesture.current = { id: p.id, start: event.clientX, x: 0 };
                  setSwipe({ id: p.id, x: 0 });
                  event.currentTarget.setPointerCapture(event.pointerId);
                }}
                onPointerMove={(event) => {
                  const current = gesture.current;
                  if (!current || current.id !== p.id) return;
                  const x = Math.max(-140, Math.min(140, event.clientX - current.start));
                  current.x = x;
                  if (Math.abs(x) > 8) dragged.current = true;
                  setSwipe({ id: p.id, x });
                }}
                onPointerUp={() => {
                  const current = gesture.current;
                  if (current?.id === p.id && Math.abs(current.x) > 72) setConfirmId(p.id);
                  gesture.current = null;
                  setSwipe(null);
                }}
                onClick={() => {
                  if (dragged.current) return;
                  onOpen(p.id);
                }}
              >
                <img src={p.photo} alt="" />
                <span>
                  <strong>{p.name}</strong>
                  <em>{p.genus}</em>
                  <small>
                    {p.vendor} · {formatDate(p.arrivedOn)}
                  </small>
                </span>
                <span className="chevron">›</span>
              </button>
            </li>
          ))}
        </ul>
      )}
      {confirmPlant && (
        <div className="confirm-sheet" role="dialog" aria-labelledby="delete-title">
          <h3 id="delete-title">Delete this plant?</h3>
          <p>Are you sure? This removes {confirmPlant.name} and its care notes from the inventory.</p>
          <button
            type="button"
            className="danger-btn"
            onClick={() => {
              onDelete(confirmPlant.id);
              setConfirmId(null);
            }}
          >
            Delete {confirmPlant.name}
          </button>
          <button type="button" className="secondary-btn" onClick={() => setConfirmId(null)}>
            Cancel
          </button>
        </div>
      )}
      <p className="sync-footer">{syncStatus}</p>
    </div>
  );
}

function SyncScreen({
  iCloudConnected,
  syncStatus,
  hasSyncTest,
  onCancel,
  onConnect,
  onDisconnect,
  onWriteTest,
}: {
  iCloudConnected: boolean;
  syncStatus: string;
  hasSyncTest: boolean;
  onCancel: () => void;
  onConnect: () => void;
  onDisconnect: () => void;
  onWriteTest: () => void;
}) {
  return (
    <div className="screen">
      <div className="nav nav-stack">
        <button className="text-btn" onClick={onCancel}>
          Done
        </button>
        <h2>Team sync</h2>
        <span />
      </div>
      <div className="form sync-form">
        <p className="hint">
          Inventory syncs plant-by-plant via iCloud. Each iPhone uses the Apple ID already signed in.
        </p>
        {iCloudConnected ? (
          <section className="sync-card">
            <strong>Connected</strong>
            <p>iCloud is active (demo).</p>
            <button type="button" className="secondary-btn" onClick={onDisconnect}>
              Use this phone only
            </button>
          </section>
        ) : (
          <section className="sync-card">
            <button type="button" className="primary-btn" onClick={onConnect}>
              Connect iCloud
            </button>
            <p className="hint">Simulates signing into iCloud on an iPhone.</p>
          </section>
        )}
        {!hasSyncTest && (
          <section className="sync-card">
            <strong>Test a record</strong>
            <button type="button" className="primary-btn" onClick={onWriteTest}>
              Write test plant + care note
            </button>
            <p className="hint">Creates one “Gardens Sync Test” plant. This section hides once any plant is already in the list.</p>
          </section>
        )}
        <p className="sync-footer">{syncStatus}</p>
      </div>
    </div>
  );
}

function AddScreen({
  catalog,
  plants,
  onCancel,
  onSave,
}: {
  catalog: CatalogType[];
  plants: Plant[];
  onCancel: () => void;
  onSave: (result: {
    catalogType: CatalogType;
    created: Plant[];
    isNewCatalog: boolean;
  }) => void;
}) {
  const [mode, setMode] = useState<"new" | "existing">("new");
  const [name, setName] = useState("");
  const [genus, setGenus] = useState("");
  const [vendor, setVendor] = useState("");
  const [arrivedOn, setArrivedOn] = useState("2026-10-24");
  const [quantity, setQuantity] = useState(1);
  const [catalogId, setCatalogId] = useState(catalog[0]?.id ?? "");
  const [care, setCare] = useState("");
  const [watering, setWatering] = useState("");
  const [health, setHealth] = useState("");

  const stocked = catalog.filter((c) => plants.some((p) => p.catalogId === c.id));
  const activeCatalogId = stocked.some((c) => c.id === catalogId) ? catalogId : (stocked[0]?.id ?? "");
  const selected = stocked.find((c) => c.id === activeCatalogId);
  const referencePhoto =
    mode === "existing"
      ? plants.find((p) => p.catalogId === activeCatalogId && p.photo)?.photo
      : undefined;

  const valid =
    quantity >= 1 &&
    vendor.trim() &&
    (mode === "existing"
      ? Boolean(selected)
      : Boolean(name.trim() && genus.trim()));

  const hint =
    mode === "new" && name.trim() && genus.trim()
      ? stocked.find(
          (c) =>
            c.name.toLowerCase() === name.trim().toLowerCase() &&
            c.genus.toLowerCase() === genus.trim().toLowerCase()
        )
        ? "Name/genus already in catalog — will reuse it and add new unique instances."
        : `Will create a new catalog type and ${quantity} unique instance${quantity === 1 ? "" : "s"}.`
      : null;

  return (
    <div className="screen">
      <div className="nav nav-stack">
        <button className="text-btn" onClick={onCancel}>
          Cancel
        </button>
        <h2>{mode === "new" ? "New arrival" : "Add more"}</h2>
        <button
          className="text-btn accent"
          disabled={!valid}
          onClick={() => {
            if (!valid) return;
            let catalogType: CatalogType;
            let isNewCatalog = false;

            if (mode === "existing" && selected) {
              catalogType = selected;
            } else {
              const match = stocked.find(
                (c) =>
                  c.name.toLowerCase() === name.trim().toLowerCase() &&
                  c.genus.toLowerCase() === genus.trim().toLowerCase()
              );
              if (match) {
                catalogType = match;
              } else {
                catalogType = {
                  id: `cat-${newId().slice(0, 8)}`,
                  name: name.trim(),
                  genus: genus.trim(),
                  care: {
                    careInstructions: care,
                    wateringCheckGuidance: watering,
                    healthCheckGuidance: health,
                  },
                };
                isNewCatalog = true;
              }
            }

            const photo =
              mode === "existing" && referencePhoto
                ? referencePhoto
                : "https://images.unsplash.com/photo-1485955900006-10f4d324d411?w=800&q=80&auto=format&fit=crop";

            const created: Plant[] = Array.from({ length: quantity }, () => ({
              id: newId(),
              catalogId: catalogType.id,
              name: catalogType.name,
              genus: catalogType.genus,
              vendor: vendor.trim(),
              arrivedOn,
              photo,
              care: catalogType.care,
              history: [],
            }));

            onSave({ catalogType, created, isNewCatalog });
          }}
        >
          {quantity > 1 ? `Save ${quantity}` : "Save"}
        </button>
      </div>

      <div className="form">
        <div className="mode-toggle" role="tablist">
          <button
            type="button"
            className={mode === "new" ? "active" : ""}
            onClick={() => setMode("new")}
          >
            New type
          </button>
          <button
            type="button"
            className={mode === "existing" ? "active" : ""}
            onClick={() => setMode("existing")}
            disabled={stocked.length === 0}
          >
            Existing type
          </button>
        </div>
        <p className="hint">
          {mode === "new"
            ? "First time this plant arrives — set the type once, then how many came in."
            : "Already on the floor — pick the type and add another shipment. Each plant still gets its own QR."}
        </p>

        {mode === "existing" && referencePhoto ? (
          <div className="photo-slot has-photo">
            <img src={referencePhoto} alt="Stored plant photo" />
            <p className="hint">Using the photo already on file for this type.</p>
          </div>
        ) : (
          <div className="photo-slot">
            <span>Plant photo</span>
            <div className="photo-actions">
              <button type="button">Choose Photo</button>
              <button type="button">Take Photo</button>
            </div>
          </div>
        )}

        {mode === "new" ? (
          <>
            <label>
              Name
              <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Snake Plant" />
            </label>
            <label>
              Genus
              <input value={genus} onChange={(e) => setGenus(e.target.value)} placeholder="Dracaena" />
            </label>
            {hint && <p className="hint">{hint}</p>}
          </>
        ) : (
          <label>
            Catalog plant
            <select value={activeCatalogId} onChange={(e) => setCatalogId(e.target.value)}>
              {stocked.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name} · {c.genus}
                </option>
              ))}
            </select>
          </label>
        )}

        <label>
          Quantity
          <div className="qty-row">
            <button type="button" onClick={() => setQuantity((q) => Math.max(1, q - 1))}>
              −
            </button>
            <input
              type="number"
              min={1}
              max={500}
              value={quantity}
              onChange={(e) => setQuantity(Math.max(1, Number(e.target.value) || 1))}
            />
            <button type="button" onClick={() => setQuantity((q) => Math.min(500, q + 1))}>
              +
            </button>
          </div>
        </label>
        <p className="hint">
          Creates {quantity} unique plant record{quantity === 1 ? "" : "s"} and QR label
          {quantity === 1 ? "" : "s"}.
        </p>

        <label>
          Date arrived
          <input type="date" value={arrivedOn} onChange={(e) => setArrivedOn(e.target.value)} />
        </label>
        <label>
          Vendor
          <input value={vendor} onChange={(e) => setVendor(e.target.value)} placeholder="Nursery name" />
        </label>

        {mode === "new" && (
          <>
            <p className="section-label">Care defaults (for new catalog types)</p>
            <label>
              Care instructions
              <textarea value={care} onChange={(e) => setCare(e.target.value)} rows={2} />
            </label>
            <label>
              How to check watering
              <textarea value={watering} onChange={(e) => setWatering(e.target.value)} rows={2} />
            </label>
            <label>
              How to check health
              <textarea value={health} onChange={(e) => setHealth(e.target.value)} rows={2} />
            </label>
          </>
        )}
      </div>
    </div>
  );
}

function BatchPrintScreen({
  plants,
  onDone,
  onPrintAll,
}: {
  plants: Plant[];
  onDone: () => void;
  onPrintAll: () => void;
}) {
  const name = plants[0]?.name ?? "Plants";
  const genus = plants[0]?.genus ?? "";

  return (
    <div className="screen">
      <div className="nav nav-stack">
        <span className="spacer" />
        <h2>Print labels</h2>
        <button className="text-btn accent" onClick={onDone}>
          Done
        </button>
      </div>
      <div className="detail">
        <h3>{name}</h3>
        <p className="genus">{genus}</p>
        <p className="meta">
          {plants.length} unique plant{plants.length === 1 ? "" : "s"} — each QR is a different
          instance ID.
        </p>
        <button className="print-btn" onClick={onPrintAll}>
          Print {plants.length} label{plants.length === 1 ? "" : "s"}
        </button>

        {plants.map((p, index) => {
          const payload = compactQR(p);
          return (
            <section className="qr-card" key={p.id}>
              <h4>
                {name} · #{index + 1} of {plants.length}
              </h4>
              <code className="payload">{p.id}</code>
              <div className="qr-wrap">
                <QRCodeSVG value={payload} size={160} level="M" includeMargin={false} />
              </div>
              <code className="payload">{payload}</code>
            </section>
          );
        })}
      </div>
    </div>
  );
}

function ScanScreen({
  plants,
  onCancel,
  onMatched,
}: {
  plants: Plant[];
  onCancel: () => void;
  onMatched: (id: string) => void;
}) {
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [cameraStatus, setCameraStatus] = useState<"idle" | "starting" | "live" | "denied" | "unsupported">(
    "idle"
  );
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const rafRef = useRef<number | null>(null);

  function resolvePlant(raw: string) {
    setError(null);
    const trimmed = raw.trim();
    let id: string | null = null;
    try {
      const parsed = JSON.parse(trimmed) as { i?: string };
      if (parsed.i) id = parsed.i;
    } catch {
      id = trimmed;
    }
    const match = plants.find((p) => p.id === id);
    if (!match) {
      setError("No plant matched that code.");
      return false;
    }
    onMatched(match.id);
    return true;
  }

  useEffect(() => {
    let cancelled = false;

    async function startCamera() {
      setCameraStatus("starting");
      if (!navigator.mediaDevices?.getUserMedia) {
        setCameraStatus("unsupported");
        return;
      }
      try {
        const stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: { ideal: "environment" } },
          audio: false,
        });
        if (cancelled) {
          stream.getTracks().forEach((t) => t.stop());
          return;
        }
        streamRef.current = stream;
        const video = videoRef.current;
        if (video) {
          video.srcObject = stream;
          await video.play();
        }
        setCameraStatus("live");

        // Prefer BarcodeDetector when the browser supports it.
        const Detector = (window as unknown as { BarcodeDetector?: new (opts: { formats: string[] }) => {
          detect: (source: HTMLVideoElement) => Promise<Array<{ rawValue: string }>>;
        } }).BarcodeDetector;

        if (Detector) {
          const detector = new Detector({ formats: ["qr_code"] });
          const tick = async () => {
            if (cancelled || !videoRef.current) return;
            try {
              const codes = await detector.detect(videoRef.current);
              if (codes[0]?.rawValue) {
                resolvePlant(codes[0].rawValue);
                return;
              }
            } catch {
              // keep scanning
            }
            rafRef.current = window.setTimeout(tick, 250) as unknown as number;
          };
          tick();
        }
      } catch {
        if (!cancelled) setCameraStatus("denied");
      }
    }

    startCamera();
    return () => {
      cancelled = true;
      if (rafRef.current) window.clearTimeout(rafRef.current);
      streamRef.current?.getTracks().forEach((t) => t.stop());
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div className="screen scan-screen">
      <div className="nav nav-stack">
        <button className="text-btn" onClick={onCancel}>
          Close
        </button>
        <h2>Scan plant</h2>
        <span className="spacer" />
      </div>

      <div className="camera-stage">
        <video ref={videoRef} className="camera-video" playsInline muted />
        <div className="camera-frame" aria-hidden />
        <p className="camera-status">
          {cameraStatus === "starting" && "Starting camera…"}
          {cameraStatus === "live" && "Point at a plant label QR"}
          {cameraStatus === "denied" && "Camera permission denied — paste a code below."}
          {cameraStatus === "unsupported" && "Camera unavailable here — paste a code below."}
          {cameraStatus === "idle" && "Preparing…"}
        </p>
      </div>

      <div className="form">
        <label>
          Or paste QR / UUID
          <textarea
            value={code}
            onChange={(e) => setCode(e.target.value)}
            rows={3}
            placeholder='{"i":"…","n":"Snake Plant","v":1}'
          />
        </label>
        <button className="print-btn" type="button" onClick={() => resolvePlant(code)}>
          Find plant
        </button>
        {error && <p className="error-text">{error}</p>}
        <p className="section-label">Try one</p>
        {plants.slice(0, 3).map((p) => (
          <button
            key={p.id}
            type="button"
            className="sample-code"
            onClick={() => setCode(compactQR(p))}
          >
            {p.name} · {p.id.slice(0, 8)}…
          </button>
        ))}
      </div>
    </div>
  );
}

function CareLogScreen({
  plant,
  onCancel,
  onSave,
}: {
  plant: Plant;
  onCancel: () => void;
  onSave: (entry: Plant["history"][number]) => void;
}) {
  const [kind, setKind] = useState("Health check");
  const [watering, setWatering] = useState("");
  const [health, setHealth] = useState("");
  const [notes, setNotes] = useState("");

  const canSave = watering.trim() || health.trim() || notes.trim() || kind !== "Note";

  return (
    <div className="screen">
      <div className="nav nav-stack">
        <button className="text-btn" onClick={onCancel}>
          Cancel
        </button>
        <h2>Log care</h2>
        <button
          className="text-btn accent"
          disabled={!canSave}
          onClick={() => {
            if (!canSave) return;
            onSave({
              kind,
              when: new Date().toLocaleString("en-US", {
                month: "short",
                day: "numeric",
                year: "numeric",
                hour: "numeric",
                minute: "2-digit",
              }),
              watering: watering.trim() || undefined,
              health: health.trim() || undefined,
              notes: notes.trim(),
            });
          }}
        >
          Save
        </button>
      </div>
      <div className="form">
        <p className="hint">
          {plant.name} · {plant.genus}
        </p>
        <p className="section-label">Guidance on file</p>
        <p className="muted">{plant.care.wateringCheckGuidance || "No watering guidance yet."}</p>
        <p className="muted">{plant.care.healthCheckGuidance || "No health guidance yet."}</p>

        <label>
          Maintenance just done
          <select value={kind} onChange={(e) => setKind(e.target.value)}>
            {[
              "Watered",
              "Fertilized",
              "Pruned",
              "Repotted",
              "Health check",
              "Note",
              "Other maintenance",
            ].map((k) => (
              <option key={k}>{k}</option>
            ))}
          </select>
        </label>
        <label>
          Watering observation
          <textarea
            value={watering}
            onChange={(e) => setWatering(e.target.value)}
            rows={3}
            placeholder="Soil dry 2&quot; down — watered thoroughly"
          />
        </label>
        <label>
          Health observation
          <textarea
            value={health}
            onChange={(e) => setHealth(e.target.value)}
            rows={3}
            placeholder="No pests; new growth on top leaves"
          />
        </label>
        <label>
          Notes
          <textarea value={notes} onChange={(e) => setNotes(e.target.value)} rows={2} />
        </label>
      </div>
    </div>
  );
}

function DetailScreen({
  plant,
  onBack,
  onLogCare,
  onPrint,
  onPhoto,
}: {
  plant: Plant;
  onBack: () => void;
  onLogCare: () => void;
  onPrint: () => void;
  onPhoto: (photo: string) => void;
}) {
  const payload = compactQR(plant);

  return (
    <div className="screen">
      <div className="nav nav-stack">
        <button className="text-btn" onClick={onBack}>
          ‹ Gardens
        </button>
        <h2>{plant.name}</h2>
        <button className="text-btn accent" onClick={onLogCare}>
          Log
        </button>
      </div>

      <div className="detail">
        <img className="hero-photo" src={plant.photo} alt={plant.name} />
        <div className="photo-edit">
          <img className="edit-photo" src={plant.photo} alt="" />
          <label className="solid-btn">
            Update photo
            <input
              type="file"
              accept="image/*"
              onChange={(event) => {
                const file = event.target.files?.[0];
                if (!file) return;
                const reader = new FileReader();
                reader.onload = () => {
                  if (typeof reader.result === "string") onPhoto(reader.result);
                };
                reader.readAsDataURL(file);
              }}
            />
          </label>
          <button
            type="button"
            className="solid-btn"
            onClick={() =>
              onPhoto(
                "https://images.unsplash.com/photo-1416879595882-3373a0480b5b?w=800&q=80&auto=format&fit=crop"
              )
            }
          >
            Use a new picture
          </button>
        </div>
        <h3>{plant.name}</h3>
        <p className="genus">{plant.genus}</p>
        <dl>
          <div>
            <dt>Vendor</dt>
            <dd>{plant.vendor}</dd>
          </div>
          <div>
            <dt>Arrived</dt>
            <dd>{formatDate(plant.arrivedOn)}</dd>
          </div>
        </dl>

        <section>
          <h4>Care</h4>
          <p>{plant.care.careInstructions || "Not set yet."}</p>
          <h4>Watering check</h4>
          <p>{plant.care.wateringCheckGuidance || "Not set yet."}</p>
          <h4>Health check</h4>
          <p>{plant.care.healthCheckGuidance || "Not set yet."}</p>
          <h4>Care history</h4>
          {plant.history.length === 0 ? (
            <p className="muted">No care events yet.</p>
          ) : (
            <ul className="history">
              {plant.history.map((h, i) => (
                <li key={i}>
                  <strong>{h.kind}</strong>
                  <small>{h.when}</small>
                  {h.watering && <span>Watering: {h.watering}</span>}
                  {h.health && <span>Health: {h.health}</span>}
                  {h.notes && <span>{h.notes}</span>}
                </li>
              ))}
            </ul>
          )}
          <div className="care-actions">
            <button className="print-btn solid-btn" type="button" onClick={onLogCare}>
              Log care / health update
            </button>
          </div>
        </section>

        <section className="qr-card">
          <h4>Label QR</h4>
          <p>
            Encodes this instance’s ID plus a compact name. Full care history loads from the store
            by ID.
          </p>
          <div className="qr-wrap">
            <QRCodeSVG value={payload} size={180} level="M" includeMargin={false} />
          </div>
          <code className="payload">{payload}</code>
          <button className="print-btn" onClick={onPrint}>
            Print label
          </button>
        </section>
      </div>
    </div>
  );
}
