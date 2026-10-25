import { useEffect, useMemo, useState } from "react";
import { QRCodeSVG } from "qrcode.react";
import "./App.css";

type CareProfile = {
  careInstructions: string;
  wateringCheckGuidance: string;
  healthCheckGuidance: string;
};

type Plant = {
  id: string;
  name: string;
  genus: string;
  vendor: string;
  arrivedOn: string;
  photo: string;
  care: CareProfile;
  history: { kind: string; when: string; notes: string }[];
};

const SAMPLE: Plant[] = [
  {
    id: "7F3A9C21-4B8E-4D12-9A01-E2C45B678901",
    name: "Snake Plant",
    genus: "Dracaena",
    vendor: "Green Harbor Nursery",
    arrivedOn: "2026-10-22",
    photo:
      "https://images.unsplash.com/photo-1593691509543-c55fb32e5cee?w=800&q=80&auto=format&fit=crop",
    care: {
      careInstructions: "Bright indirect light. Allow soil to dry between waterings.",
      wateringCheckGuidance: "Probe 2 inches down — water only if dry.",
      healthCheckGuidance: "Yellow tips usually mean overwatering; soft leaves mean cold draft.",
    },
    history: [
      { kind: "Watered", when: "Oct 23, 2026", notes: "Light soak" },
      { kind: "Health check", when: "Oct 22, 2026", notes: "Arrived healthy" },
    ],
  },
  {
    id: "A91C2D34-55E6-4F78-B901-C234567890AB",
    name: "Fiddle Leaf Fig",
    genus: "Ficus",
    vendor: "Westside Growers",
    arrivedOn: "2026-10-20",
    photo:
      "https://images.unsplash.com/photo-1459411552884-841db9b3cc2a?w=800&q=80&auto=format&fit=crop",
    care: {
      careInstructions: "Consistent bright light; wipe leaves monthly.",
      wateringCheckGuidance: "Lift the pot — water when it feels light.",
      healthCheckGuidance: "Brown spots can be inconsistent watering or low humidity.",
    },
    history: [],
  },
  {
    id: "B02D3E45-66F7-4089-C012-D345678901BC",
    name: "Monstera Deliciosa",
    genus: "Monstera",
    vendor: "Green Harbor Nursery",
    arrivedOn: "2026-10-18",
    photo:
      "https://images.unsplash.com/photo-1614594975525-e45190c55d0b?w=800&q=80&auto=format&fit=crop",
    care: {
      careInstructions: "Moss pole optional. Keep soil lightly moist in growing season.",
      wateringCheckGuidance: "Check top inch of soil every few days.",
      healthCheckGuidance: "Yellow oldest leaves are normal; check for pests under leaves.",
    },
    history: [{ kind: "Repotted", when: "Oct 19, 2026", notes: "Into 8-inch nursery pot" }],
  },
];

type Screen = "list" | "add" | "detail";

function compactQR(plant: Plant) {
  return JSON.stringify({
    i: plant.id,
    n: plant.name.slice(0, 80),
    v: 1,
  });
}

function formatDate(iso: string) {
  return new Date(iso + "T12:00:00").toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

export default function App() {
  const [plants, setPlants] = useState<Plant[]>(SAMPLE);
  const [screen, setScreen] = useState<Screen>("list");
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [printNote, setPrintNote] = useState<string | null>(null);
  const [showSplash, setShowSplash] = useState(true);

  useEffect(() => {
    const t = window.setTimeout(() => setShowSplash(false), 1800);
    return () => window.clearTimeout(t);
  }, []);

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
          Interactive mock of the SwiftUI intake flow. Open{" "}
          <code>Gardens/Gardens.xcodeproj</code> on a Mac for the real app.
        </p>
        {showSplash && (
          <button type="button" className="skip-splash" onClick={() => setShowSplash(false)}>
            Skip splash
          </button>
        )}
      </header>

      <div className="phone" aria-label="iPhone preview">
        <div className="notch" aria-hidden />
        <div className="status-bar">
          <span>9:41</span>
          <span className="status-icons">●●● ▮</span>
        </div>

        {showSplash && <SplashScreen />}

        {!showSplash && screen === "list" && (
          <ListScreen
            plants={plants}
            onAdd={() => setScreen("add")}
            onOpen={(id) => {
              setSelectedId(id);
              setScreen("detail");
            }}
          />
        )}

        {!showSplash && screen === "add" && (
          <AddScreen
            existing={plants}
            onCancel={() => setScreen("list")}
            onSave={(plant) => {
              setPlants((prev) => [plant, ...prev]);
              setSelectedId(plant.id);
              setScreen("detail");
            }}
          />
        )}

        {!showSplash && screen === "detail" && selected && (
          <DetailScreen
            plant={selected}
            onBack={() => setScreen("list")}
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

function SplashScreen() {
  return (
    <div className="splash" role="img" aria-label="Gardens splash">
      <div className="splash-orb" aria-hidden />
      <div className="splash-mark" aria-hidden>
        <svg viewBox="0 0 64 64" width="56" height="56" fill="none">
          <path
            d="M32 8c-2 14-14 22-20 26 10 2 18 10 20 22 2-12 10-20 20-22-6-4-18-12-20-26Z"
            fill="url(#leaf)"
          />
          <defs>
            <linearGradient id="leaf" x1="12" y1="8" x2="48" y2="56" gradientUnits="userSpaceOnUse">
              <stop stopColor="#b8e0b2" />
              <stop offset="1" stopColor="#4fa35a" />
            </linearGradient>
          </defs>
        </svg>
      </div>
      <h2 className="splash-title">Gardens</h2>
      <p className="splash-sub">Plant intake</p>
    </div>
  );
}

function ListScreen({
  plants,
  onAdd,
  onOpen,
}: {
  plants: Plant[];
  onAdd: () => void;
  onOpen: (id: string) => void;
}) {
  return (
    <div className="screen">
      <div className="nav">
        <h2>Gardens</h2>
        <button className="icon-btn" onClick={onAdd} aria-label="Add plant">
          +
        </button>
      </div>
      {plants.length === 0 ? (
        <div className="empty">
          <div className="empty-glyph">🌿</div>
          <h3>No plants yet</h3>
          <p>Add an arrival to start your inventory.</p>
        </div>
      ) : (
        <ul className="plant-list">
          {plants.map((p) => (
            <li key={p.id}>
              <button className="plant-row" onClick={() => onOpen(p.id)}>
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
    </div>
  );
}

function AddScreen({
  existing,
  onCancel,
  onSave,
}: {
  existing: Plant[];
  onCancel: () => void;
  onSave: (plant: Plant) => void;
}) {
  const [name, setName] = useState("");
  const [genus, setGenus] = useState("");
  const [vendor, setVendor] = useState("");
  const [arrivedOn, setArrivedOn] = useState("2026-10-24");
  const [care, setCare] = useState("");
  const [watering, setWatering] = useState("");
  const [health, setHealth] = useState("");

  const match = existing.find(
    (p) =>
      p.name.trim().toLowerCase() === name.trim().toLowerCase() &&
      p.genus.trim().toLowerCase() === genus.trim().toLowerCase()
  );

  const valid = name.trim() && genus.trim() && vendor.trim();

  return (
    <div className="screen">
      <div className="nav nav-stack">
        <button className="text-btn" onClick={onCancel}>
          Cancel
        </button>
        <h2>New plant</h2>
        <button
          className="text-btn accent"
          disabled={!valid}
          onClick={() => {
            if (!valid) return;
            onSave({
              id: crypto.randomUUID().toUpperCase(),
              name: name.trim(),
              genus: genus.trim(),
              vendor: vendor.trim(),
              arrivedOn,
              photo:
                "https://images.unsplash.com/photo-1485955900006-10f4d324d411?w=800&q=80&auto=format&fit=crop",
              care: {
                careInstructions: care,
                wateringCheckGuidance: watering,
                healthCheckGuidance: health,
              },
              history: [],
            });
          }}
        >
          Save
        </button>
      </div>

      <div className="form">
        <div className="photo-slot">
          <span>Plant photo</span>
          <div className="photo-actions">
            <button type="button">Choose Photo</button>
            <button type="button">Take Photo</button>
          </div>
        </div>

        <label>
          Name
          <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Snake Plant" />
        </label>
        <label>
          Genus
          <input value={genus} onChange={(e) => setGenus(e.target.value)} placeholder="Dracaena" />
        </label>
        {match ? (
          <p className="hint">Will reuse catalog entry “{match.name}” ({match.genus}).</p>
        ) : valid ? (
          <p className="hint">Will create a new catalog entry.</p>
        ) : null}

        <label>
          Date arrived
          <input type="date" value={arrivedOn} onChange={(e) => setArrivedOn(e.target.value)} />
        </label>
        <label>
          Vendor
          <input value={vendor} onChange={(e) => setVendor(e.target.value)} placeholder="Nursery name" />
        </label>

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
      </div>
    </div>
  );
}

function DetailScreen({
  plant,
  onBack,
  onPrint,
}: {
  plant: Plant;
  onBack: () => void;
  onPrint: () => void;
}) {
  const payload = compactQR(plant);

  return (
    <div className="screen">
      <div className="nav nav-stack">
        <button className="text-btn" onClick={onBack}>
          ‹ Gardens
        </button>
        <h2>{plant.name}</h2>
        <span className="spacer" />
      </div>

      <div className="detail">
        <img className="hero-photo" src={plant.photo} alt={plant.name} />
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
                  {h.notes && <span>{h.notes}</span>}
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="qr-card">
          <h4>Label QR</h4>
          <p>
            Encodes this instance’s ID plus a compact name. Full care history loads from the
            store by ID.
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
