import { useEffect, useMemo, useState } from "react";
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
      "https://images.unsplash.com/photo-1593691509543-c55fb32e5cee?w=800&q=80&auto=format&fit=crop",
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

type Screen = "list" | "add" | "detail" | "batch" | "scan" | "care";

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

  useEffect(() => {
    if (!showSplash) return;
    const t = window.setTimeout(() => setShowSplash(false), 1800);
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
          Existing type reuses the stored photo. Use <strong>Scan</strong> to look up a QR and log
          watering / health / maintenance.
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
            onAdd={() => setScreen("add")}
            onScan={() => setScreen("scan")}
            onOpen={(id) => {
              setSelectedId(id);
              setScreen("detail");
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

type SplashStyle = "leafMark" | "wordmark" | "largeLogo";

const SPLASH_STYLES: SplashStyle[] = ["leafMark", "wordmark", "largeLogo"];

function randomSplashStyle(): SplashStyle {
  return SPLASH_STYLES[Math.floor(Math.random() * SPLASH_STYLES.length)];
}

function SplashScreen({ style }: { style: SplashStyle }) {
  return (
    <div className={`splash splash-${style}`} role="img" aria-label="Gardens splash">
      <div className="splash-orb" aria-hidden />
      {style === "leafMark" && (
        <div className="splash-mark" aria-hidden>
          <svg viewBox="0 0 64 64" width="56" height="56" fill="none">
            <path
              d="M32 8c-2 14-14 22-20 26 10 2 18 10 20 22 2-12 10-20 20-22-6-4-18-12-20-26Z"
              fill="url(#leaf)"
            />
            <defs>
              <linearGradient
                id="leaf"
                x1="12"
                y1="8"
                x2="48"
                y2="56"
                gradientUnits="userSpaceOnUse"
              >
                <stop stopColor="#b8e0b2" />
                <stop offset="1" stopColor="#4fa35a" />
              </linearGradient>
            </defs>
          </svg>
        </div>
      )}
      {style === "wordmark" && (
        <div className="splash-initial" aria-hidden>
          G
        </div>
      )}
      {style === "largeLogo" && (
        <img
          className="splash-logo-img"
          src="/brand-mark.png"
          alt="The Gardens"
        />
      )}
      {style === "wordmark" && <h2 className="splash-title">Gardens</h2>}
      {style === "leafMark" && <h2 className="splash-title">Gardens</h2>}
      <p className="splash-sub">Plant intake</p>
      <p className="splash-variant">Splash: {style}</p>
    </div>
  );
}

function ListScreen({
  plants,
  onAdd,
  onScan,
  onOpen,
}: {
  plants: Plant[];
  onAdd: () => void;
  onScan: () => void;
  onOpen: (id: string) => void;
}) {
  return (
    <div className="screen">
      <div className="nav">
        <button className="text-btn" onClick={onScan} aria-label="Scan plant">
          ⌁ Scan
        </button>
        <h2>Gardens</h2>
        <button className="icon-btn" onClick={onAdd} aria-label="Add plant">
          +
        </button>
      </div>
      {plants.length === 0 ? (
        <div className="empty">
          <div className="empty-glyph">🌿</div>
          <h3>No plants yet</h3>
          <p>Log an arrival — one plant or a whole carton.</p>
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

  const selected = catalog.find((c) => c.id === catalogId);
  const referencePhoto =
    mode === "existing"
      ? plants.find((p) => p.catalogId === catalogId && p.photo)?.photo
      : undefined;

  const valid =
    quantity >= 1 &&
    vendor.trim() &&
    (mode === "existing"
      ? Boolean(selected)
      : Boolean(name.trim() && genus.trim()));

  const hint =
    mode === "new" && name.trim() && genus.trim()
      ? catalog.find(
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
              const match = catalog.find(
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
            disabled={catalog.length === 0}
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
            <select value={catalogId} onChange={(e) => setCatalogId(e.target.value)}>
              {catalog.map((c) => (
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

  function findPlant() {
    setError(null);
    const trimmed = code.trim();
    let id: string | null = null;
    try {
      const parsed = JSON.parse(trimmed) as { i?: string };
      if (parsed.i) id = parsed.i;
    } catch {
      id = trimmed;
    }
    const match = plants.find((p) => p.id === id);
    if (!match) {
      setError("No plant matched that code. Paste a QR JSON or instance UUID.");
      return;
    }
    onMatched(match.id);
  }

  return (
    <div className="screen">
      <div className="nav nav-stack">
        <button className="text-btn" onClick={onCancel}>
          Close
        </button>
        <h2>Scan plant</h2>
        <span className="spacer" />
      </div>
      <div className="form">
        <p className="hint">
          Paste QR contents or an instance UUID (camera scan wires to the same lookup in the iOS
          app).
        </p>
        <label>
          QR / UUID
          <textarea
            value={code}
            onChange={(e) => setCode(e.target.value)}
            rows={4}
            placeholder='{"i":"…","n":"Snake Plant","v":1}'
          />
        </label>
        <button className="print-btn" type="button" onClick={findPlant}>
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
}: {
  plant: Plant;
  onBack: () => void;
  onLogCare: () => void;
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
        <button className="text-btn accent" onClick={onLogCare}>
          Log
        </button>
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
                  {h.watering && <span>Watering: {h.watering}</span>}
                  {h.health && <span>Health: {h.health}</span>}
                  {h.notes && <span>{h.notes}</span>}
                </li>
              ))}
            </ul>
          )}
          <button className="print-btn" type="button" onClick={onLogCare} style={{ marginTop: 12 }}>
            Log care / health update
          </button>
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
