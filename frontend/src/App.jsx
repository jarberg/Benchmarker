import { useState, useEffect, useCallback } from "react";

const API = ""; // Vite proxies /jobs and /configs → localhost:8000

const STATUS_COLOR = {
  pending:   "#f59e0b",
  running:   "#38bdf8",
  completed: "#4ade80",
  failed:    "#f87171",
};

const ENGINE_LABEL = {
  unreal:  "Unreal Engine",
  unity:   "Unity",
  generic: "Generic",
};

// ─── fetch helpers ────────────────────────────────────────────────────────────

async function apiGet(path) {
  const res = await fetch(API + path);
  if (!res.ok) throw new Error(await res.text());
  return res.json();
}

async function apiPost(path, body) {
  const res = await fetch(API + path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(await res.text());
  return res.json();
}

async function apiPostForm(path, formData) {
  const res = await fetch(API + path, { method: "POST", body: formData });
  if (!res.ok) throw new Error(await res.text());
  return res.json();
}

// ─── StatusBadge ─────────────────────────────────────────────────────────────

function StatusBadge({ status }) {
  return (
    <span style={{
      padding: "2px 10px",
      borderRadius: 12,
      fontSize: 12,
      fontWeight: 600,
      background: STATUS_COLOR[status] + "22",
      color: STATUS_COLOR[status] ?? "#94a3b8",
      border: `1px solid ${STATUS_COLOR[status] ?? "#334155"}`,
      textTransform: "uppercase",
      letterSpacing: "0.05em",
    }}>
      {status}
    </span>
  );
}

function EngineBadge({ engine }) {
  const colors = { unreal: "#818cf8", unity: "#34d399", generic: "#94a3b8" };
  const color = colors[engine] ?? "#94a3b8";
  return (
    <span style={{
      padding: "2px 8px",
      borderRadius: 10,
      fontSize: 11,
      fontWeight: 600,
      background: color + "18",
      color,
      border: `1px solid ${color}44`,
    }}>
      {ENGINE_LABEL[engine] ?? engine ?? "—"}
    </span>
  );
}

// ─── shared styles ────────────────────────────────────────────────────────────

const inputStyle = {
  width: "100%",
  padding: "8px 12px",
  background: "#1e2433",
  border: "1px solid #334155",
  borderRadius: 6,
  color: "#e2e8f0",
  fontSize: 14,
};

const labelStyle = {
  display: "block",
  fontSize: 13,
  color: "#94a3b8",
  marginBottom: 4,
};

// ─── SubmitForm ───────────────────────────────────────────────────────────────

function SubmitForm({ onSubmitted, configs }) {
  const [name, setName]           = useState("");
  const [file, setFile]           = useState(null);
  const [duration, setDuration]   = useState(60);
  const [executable, setExec]     = useState("");
  const [exeConfig, setExeConfig] = useState("generic");
  const [mock, setMock]           = useState(false);
  const [loading, setLoading]     = useState(false);
  const [error, setError]         = useState(null);

  // When a saved preset is chosen, pre-fill the form fields from it
  function applyPreset(presetId) {
    if (!presetId) return;
    const preset = configs.find(c => c.id === presetId);
    if (!preset?.config) return;
    const c = preset.config;
    if (c.exeConfig)          setExeConfig(c.exeConfig);
    if (c.duration_seconds)   setDuration(c.duration_seconds);
    if (c.executable)         setExec(c.executable);
  }

  async function handleSubmit(e) {
    e.preventDefault();
    setError(null);
    setLoading(true);

    try {
      const config = JSON.stringify({
        duration_seconds: Number(duration),
        executable,
        exeConfig,
        mock,
        args: [],
        resolution: "1920x1080",
        quality_preset: "high",
      });

      const fd = new FormData();
      fd.append("game_name", name || (mock ? "mock-run" : file?.name ?? "unnamed"));
      fd.append("config", config);

      if (mock) {
        fd.append("file", new Blob([new Uint8Array([0])], { type: "application/octet-stream" }), "mock.bin");
      } else {
        if (!file) { setError("Please select a game file."); setLoading(false); return; }
        fd.append("file", file);
      }

      const job = await apiPostForm("/jobs", fd);
      onSubmitted(job);

      // Reset
      setName(""); setFile(null); setDuration(60); setExec("");
      setExeConfig("generic"); setMock(false);
      if (e.target.fileInput) e.target.fileInput.value = "";
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div style={{ background: "#161b27", border: "1px solid #1e2d45", borderRadius: 10, padding: 24 }}>
      <h2 style={{ fontSize: 16, fontWeight: 600, marginBottom: 20, color: "#e2e8f0" }}>
        Submit Benchmark Job
      </h2>

      <form onSubmit={handleSubmit} style={{ display: "flex", flexDirection: "column", gap: 16 }}>

        {/* Saved preset loader */}
        {configs.length > 0 && (
          <div>
            <label style={labelStyle}>Load preset</label>
            <select style={inputStyle} defaultValue="" onChange={e => applyPreset(e.target.value)}>
              <option value="">— choose a preset —</option>
              {configs.map(c => (
                <option key={c.id} value={c.id}>{c.name ?? c.id.slice(0, 8)}</option>
              ))}
            </select>
          </div>
        )}

        {/* Mock toggle */}
        <label style={{ display: "flex", alignItems: "center", gap: 10, cursor: "pointer" }}>
          <input type="checkbox" checked={mock} onChange={e => setMock(e.target.checked)}
            style={{ width: 16, height: 16, accentColor: "#6366f1" }} />
          <span style={{ fontSize: 14, color: "#94a3b8" }}>
            Mock run <span style={{ color: "#475569" }}>(simulate — no real game needed)</span>
          </span>
        </label>

        {/* Engine type */}
        <div>
          <label style={labelStyle}>Engine</label>
          <select style={inputStyle} value={exeConfig} onChange={e => setExeConfig(e.target.value)}>
            <option value="generic">Generic</option>
            <option value="unreal">Unreal Engine</option>
            <option value="unity">Unity</option>
          </select>
        </div>

        {/* Game name */}
        <div>
          <label style={labelStyle}>Game name</label>
          <input style={inputStyle} type="text"
            placeholder={mock ? "mock-run" : "My Game v1.2"}
            value={name} onChange={e => setName(e.target.value)} />
        </div>

        {/* File upload */}
        {!mock && (
          <div>
            <label style={labelStyle}>
              Game file <span style={{ color: "#475569" }}>(.zip, .tar.gz, or executable)</span>
            </label>
            <input name="fileInput" style={{ ...inputStyle, padding: "6px 12px" }}
              type="file" onChange={e => setFile(e.target.files[0])} />
          </div>
        )}

        {/* Executable path */}
        {!mock && (
          <div>
            <label style={labelStyle}>
              Executable path <span style={{ color: "#475569" }}>(relative inside archive)</span>
            </label>
            <input style={inputStyle} type="text"
              placeholder={exeConfig === "unreal" ? "Binaries/Win64/MyGame.exe" : "bin/game.exe"}
              value={executable} onChange={e => setExec(e.target.value)} />
          </div>
        )}

        {/* Unreal hint */}
        {exeConfig === "unreal" && !mock && (
          <div style={{ padding: "8px 12px", background: "#818cf811", border: "1px solid #818cf833", borderRadius: 6, fontSize: 12, color: "#a5b4fc" }}>
            Unreal mode: worker will launch with <code>-csvprofile -trace=cpu,gpu,frame,memory</code> and parse CSV output from <code>Saved/Profiling/CSV/</code>
          </div>
        )}

        {/* Duration */}
        <div>
          <label style={labelStyle}>
            Duration: <strong style={{ color: "#e2e8f0" }}>{duration}s</strong>
          </label>
          <input type="range" min={5} max={300} step={5} value={duration}
            onChange={e => setDuration(e.target.value)}
            style={{ width: "100%", accentColor: "#6366f1" }} />
          <div style={{ display: "flex", justifyContent: "space-between", fontSize: 11, color: "#475569", marginTop: 2 }}>
            <span>5s</span><span>300s</span>
          </div>
        </div>

        {error && (
          <div style={{ padding: "10px 14px", background: "#f8717122", border: "1px solid #f87171", borderRadius: 6, color: "#fca5a5", fontSize: 13 }}>
            {error}
          </div>
        )}

        <button type="submit" disabled={loading} style={{
          padding: "10px 20px",
          background: loading ? "#312e81" : "#4f46e5",
          color: "#fff",
          border: "none",
          borderRadius: 6,
          fontSize: 14,
          fontWeight: 600,
          transition: "background 0.15s",
        }}>
          {loading ? "Submitting…" : "Submit Job"}
        </button>
      </form>
    </div>
  );
}

// ─── SavePresetModal ──────────────────────────────────────────────────────────

function SavePresetModal({ onSave, onClose }) {
  const [name, setName]           = useState("");
  const [exeConfig, setExeConfig] = useState("generic");
  const [duration, setDuration]   = useState(60);
  const [executable, setExec]     = useState("");
  const [saving, setSaving]       = useState(false);

  async function handleSave(e) {
    e.preventDefault();
    setSaving(true);
    try {
      await onSave({ name, config: { exeConfig, duration_seconds: duration, executable } });
      onClose();
    } finally {
      setSaving(false);
    }
  }

  return (
    <div style={{ position: "fixed", inset: 0, background: "#000a", display: "flex", alignItems: "center", justifyContent: "center", zIndex: 50 }}>
      <div style={{ background: "#161b27", border: "1px solid #1e2d45", borderRadius: 12, padding: 28, width: 380 }}>
        <h3 style={{ fontSize: 15, fontWeight: 600, marginBottom: 18 }}>Save Config Preset</h3>
        <form onSubmit={handleSave} style={{ display: "flex", flexDirection: "column", gap: 14 }}>
          <div>
            <label style={labelStyle}>Preset name</label>
            <input style={inputStyle} required value={name} onChange={e => setName(e.target.value)} placeholder="UE5 High 1080p" />
          </div>
          <div>
            <label style={labelStyle}>Engine</label>
            <select style={inputStyle} value={exeConfig} onChange={e => setExeConfig(e.target.value)}>
              <option value="generic">Generic</option>
              <option value="unreal">Unreal Engine</option>
              <option value="unity">Unity</option>
            </select>
          </div>
          <div>
            <label style={labelStyle}>Default duration (s)</label>
            <input style={inputStyle} type="number" min={5} max={300} value={duration} onChange={e => setDuration(Number(e.target.value))} />
          </div>
          <div>
            <label style={labelStyle}>Default executable path</label>
            <input style={inputStyle} value={executable} onChange={e => setExec(e.target.value)} placeholder="Binaries/Win64/MyGame.exe" />
          </div>
          <div style={{ display: "flex", gap: 8, justifyContent: "flex-end" }}>
            <button type="button" onClick={onClose} style={{ ...btnBase, background: "#1e2433", color: "#94a3b8" }}>Cancel</button>
            <button type="submit" disabled={saving} style={{ ...btnBase, background: "#4f46e5", color: "#fff" }}>
              {saving ? "Saving…" : "Save preset"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

const btnBase = { padding: "8px 16px", border: "none", borderRadius: 6, fontSize: 13, fontWeight: 600, cursor: "pointer" };

// ─── JobRow ───────────────────────────────────────────────────────────────────

function JobRow({ job, onSelect, selected }) {
  const created = job.created_at?.slice(0, 19).replace("T", " ");
  const engine  = job.config?.exeConfig;
  return (
    <tr onClick={() => onSelect(job.id)} style={{
      cursor: "pointer",
      background: selected ? "#1e2d4555" : "transparent",
      transition: "background 0.1s",
    }}>
      <td style={td}><code style={{ fontSize: 11, color: "#64748b" }}>{job.id.slice(0, 8)}…</code></td>
      <td style={td}>{job.game_name}</td>
      <td style={td}><EngineBadge engine={engine} /></td>
      <td style={td}><StatusBadge status={job.status} /></td>
      <td style={td}><span style={{ color: "#64748b", fontSize: 12 }}>{job.worker_id ?? "—"}</span></td>
      <td style={td}><span style={{ color: "#64748b", fontSize: 12 }}>{created}</span></td>
    </tr>
  );
}

const th = {
  padding: "8px 12px", textAlign: "left", fontSize: 12, color: "#475569",
  fontWeight: 600, borderBottom: "1px solid #1e2d45", textTransform: "uppercase", letterSpacing: "0.05em",
};
const td = { padding: "10px 12px", borderBottom: "1px solid #1a2233", fontSize: 14 };

// ─── ResultsPanel ─────────────────────────────────────────────────────────────

function ResultsPanel({ job }) {
  if (!job) return null;

  const res     = job.results;
  const metrics = res?.metrics;
  const fps     = res?.fps;
  const ue      = res?.unreal;          // Unreal-specific metrics
  const engine  = job.config?.exeConfig;

  return (
    <div style={{ background: "#161b27", border: "1px solid #1e2d45", borderRadius: 10, padding: 20, marginTop: 20 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 16, flexWrap: "wrap" }}>
        <h3 style={{ fontSize: 15, fontWeight: 600 }}>Job Details</h3>
        <StatusBadge status={job.status} />
        <EngineBadge engine={engine} />
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8, fontSize: 13, marginBottom: 16 }}>
        <Kv k="ID"      v={<code style={{ fontSize: 11 }}>{job.id}</code>} />
        <Kv k="Game"    v={job.game_name} />
        <Kv k="Worker"  v={job.worker_id ?? "—"} />
        <Kv k="Created" v={job.created_at?.slice(0, 19).replace("T", " ")} />
      </div>

      {job.status === "failed" && (
        <div style={{ padding: "10px 14px", background: "#f8717122", border: "1px solid #f87171", borderRadius: 6, color: "#fca5a5", fontSize: 13 }}>
          {job.error ?? "Unknown error"}
        </div>
      )}

      {(job.status === "pending" || job.status === "running") && (
        <div style={{ color: "#64748b", fontSize: 13 }}>Waiting for results…</div>
      )}

      {res && (
        <>
          {/* Unreal Engine thread breakdown */}
          {ue && (
            <div style={{ marginTop: 12 }}>
              <SectionLabel>Unreal Thread Times (ms)</SectionLabel>
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 8 }}>
                <MetricCard label="Game Thread" value={`${ue.game_thread_ms?.avg} ms`} sub={`p95 ${ue.game_thread_ms?.p95} ms`} />
                <MetricCard label="Render Thread" value={`${ue.render_thread_ms?.avg} ms`} sub={`p95 ${ue.render_thread_ms?.p95} ms`} />
                <MetricCard label="GPU" value={`${ue.gpu_ms?.avg} ms`} sub={`p95 ${ue.gpu_ms?.p95} ms`} />
              </div>
              {ue.draw_calls?.avg && (
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 8, marginTop: 8 }}>
                  <MetricCard label="Draw Calls" value={ue.draw_calls?.avg} />
                  <MetricCard label="Triangles" value={ue.triangles?.avg ? `${(ue.triangles.avg / 1e6).toFixed(2)}M` : "—"} />
                  <MetricCard label="CSV rows" value={ue.sample_count} />
                </div>
              )}
            </div>
          )}

          {/* FPS */}
          {fps && (
            <div style={{ marginTop: 12 }}>
              <SectionLabel>FPS</SectionLabel>
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr 1fr", gap: 8 }}>
                <MetricCard label="Avg" value={fps.avg} />
                <MetricCard label="Min" value={fps.min} />
                <MetricCard label="Max" value={fps.max} />
                <MetricCard label="1% Low" value={fps.p1_low} />
              </div>
            </div>
          )}

          {/* System metrics */}
          {metrics && (
            <div style={{ marginTop: 12 }}>
              <SectionLabel>System</SectionLabel>
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 8 }}>
                <MetricCard label="CPU avg" value={`${metrics.cpu_percent?.avg}%`} />
                <MetricCard label="CPU p95" value={`${metrics.cpu_percent?.p95}%`} />
                <MetricCard label="Mem avg" value={`${metrics.memory_mb?.avg} MB`} />
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}

function SectionLabel({ children }) {
  return (
    <div style={{ fontSize: 12, color: "#475569", marginBottom: 8, fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.05em" }}>
      {children}
    </div>
  );
}

function MetricCard({ label, value, sub }) {
  return (
    <div style={{ background: "#1e2433", borderRadius: 6, padding: "10px 14px" }}>
      <div style={{ fontSize: 11, color: "#475569", marginBottom: 4, textTransform: "uppercase", letterSpacing: "0.05em" }}>{label}</div>
      <div style={{ fontSize: 18, fontWeight: 700, color: "#e2e8f0" }}>{value ?? "—"}</div>
      {sub && <div style={{ fontSize: 11, color: "#475569", marginTop: 2 }}>{sub}</div>}
    </div>
  );
}

function Kv({ k, v }) {
  return (
    <div>
      <span style={{ color: "#475569", marginRight: 6 }}>{k}:</span>
      <span style={{ color: "#cbd5e1" }}>{v}</span>
    </div>
  );
}

// ─── App ─────────────────────────────────────────────────────────────────────

export default function App() {
  const [jobs, setJobs]           = useState([]);
  const [configs, setConfigs]     = useState([]);
  const [selectedId, setSelected] = useState(null);
  const [selectedJob, setSelJob]  = useState(null);
  const [apiOk, setApiOk]         = useState(null);
  const [showPreset, setShowPreset] = useState(false);

  useEffect(() => {
    apiGet("/health").then(() => setApiOk(true)).catch(() => setApiOk(false));
  }, []);

  const fetchJobs = useCallback(() => {
    apiGet("/jobs?limit=50").then(setJobs).catch(() => {});
  }, []);

  const fetchConfigs = useCallback(() => {
    apiGet("/configs").then(setConfigs).catch(() => {});
  }, []);

  useEffect(() => {
    fetchJobs();
    fetchConfigs();
    const t = setInterval(fetchJobs, 3000);
    return () => clearInterval(t);
  }, [fetchJobs, fetchConfigs]);

  useEffect(() => {
    if (!selectedId) return;
    const j = jobs.find(j => j.id === selectedId);
    if (j) setSelJob(j);
  }, [jobs, selectedId]);

  function handleSelect(id) {
    setSelected(id);
    setSelJob(jobs.find(j => j.id === id) ?? null);
  }

  function handleSubmitted(job) {
    setJobs(prev => [job, ...prev]);
    setSelected(job.id);
    setSelJob(job);
  }

  async function handleSavePreset(data) {
    await apiPost("/configs", data);
    fetchConfigs();
  }

  return (
    <div style={{ maxWidth: 1200, margin: "0 auto", padding: "32px 20px" }}>

      {/* Header */}
      <div style={{ display: "flex", alignItems: "center", gap: 16, marginBottom: 32 }}>
        <h1 style={{ fontSize: 22, fontWeight: 700 }}>🎮 Game Benchmark</h1>
        {apiOk === true  && <span style={{ fontSize: 12, color: "#4ade80" }}>● API connected</span>}
        {apiOk === false && <span style={{ fontSize: 12, color: "#f87171" }}>● API unreachable — is the server running?</span>}
        <button onClick={() => setShowPreset(true)} style={{
          marginLeft: "auto", ...btnBase, background: "#1e2433",
          color: "#94a3b8", border: "1px solid #334155", fontSize: 12,
        }}>
          + Save preset
        </button>
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "380px 1fr", gap: 24, alignItems: "start" }}>

        {/* Left — submit form */}
        <SubmitForm onSubmitted={handleSubmitted} configs={configs} />

        {/* Right — jobs table + detail */}
        <div>
          <div style={{ background: "#161b27", border: "1px solid #1e2d45", borderRadius: 10, overflow: "hidden" }}>
            <div style={{ padding: "14px 16px", borderBottom: "1px solid #1e2d45", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <span style={{ fontSize: 15, fontWeight: 600 }}>Jobs</span>
              <span style={{ fontSize: 12, color: "#475569" }}>auto-refreshes every 3s</span>
            </div>

            {jobs.length === 0 ? (
              <div style={{ padding: 32, textAlign: "center", color: "#475569", fontSize: 14 }}>
                No jobs yet. Submit one to get started.
              </div>
            ) : (
              <table style={{ width: "100%", borderCollapse: "collapse" }}>
                <thead>
                  <tr>
                    <th style={th}>ID</th>
                    <th style={th}>Game</th>
                    <th style={th}>Engine</th>
                    <th style={th}>Status</th>
                    <th style={th}>Worker</th>
                    <th style={th}>Created</th>
                  </tr>
                </thead>
                <tbody>
                  {jobs.map(j => (
                    <JobRow key={j.id} job={j} onSelect={handleSelect} selected={j.id === selectedId} />
                  ))}
                </tbody>
              </table>
            )}
          </div>

          {selectedJob && <ResultsPanel job={selectedJob} />}
        </div>
      </div>

      {showPreset && (
        <SavePresetModal
          onSave={handleSavePreset}
          onClose={() => setShowPreset(false)}
        />
      )}
    </div>
  );
}
