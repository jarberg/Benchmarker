import { useEffect, useState, useCallback } from "react";
import { router } from "@inertiajs/react";
import axios from "axios";
import { Gamepad2, Plus } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger, DialogClose
} from "@/components/ui/dialog";

const ENGINE_LABEL = { unreal: "Unreal Engine", unity: "Unity", generic: "Generic" };

// ─────────────────────────────────────────────────────────────────────────────

export default function Dashboard({ jobs: initialJobs = [], configs: initialConfigs = [] }) {
    const [jobs, setJobs] = useState(initialJobs);
    const [configs, setConfigs] = useState(initialConfigs);
    const [selectedId, setSelected] = useState(null);
    const [apiOk, setApiOk] = useState(null);

    useEffect(() => {
        axios.get("/api/health").then(() => setApiOk(true)).catch(() => setApiOk(false));
    }, []);

    const refreshJobs = useCallback(async () => {
    try {
        const { data } = await axios.get("/jsonapi/jobs");
        const rows = (data?.data ?? []).map(d => ({ id: d.id, ...d.attributes }));
        setJobs(rows);
    } catch (_) { /* ignore */ }
    }, []);

    const refreshConfigs = useCallback(async () => {
    try {
        const { data } = await axios.get("/jsonapi/configs");
        setConfigs((data?.data ?? []).map(d => ({ id: d.id, ...d.attributes })));
    } catch (_) { /* ignore */ }
    }, []);

    useEffect(() => {
        const t = setInterval(refreshJobs, 3000);
    return () => clearInterval(t);
    }, [refreshJobs]);

    const selectedJob = jobs.find(j => j.id === selectedId) ?? null;

  return (
    <div className="mx-auto max-w-6xl px-5 py-8">
      <header className="mb-8 flex flex-wrap items-center gap-4">
        <h1 className="flex items-center gap-2 text-2xl font-bold">
          <Gamepad2 className="h-6 w-6 text-primary" />
          Game Benchmark
        </h1>
        {apiOk === true  && <span className="text-xs text-emerald-400">● API connected</span>}
        {apiOk === false && <span className="text-xs text-rose-400">● API unreachable</span>}
        <div className="ml-auto">
          <SavePresetDialog onSaved={refreshConfigs} />
        </div>
      </header>

      <div className="grid grid-cols-1 items-start gap-6 lg:grid-cols-[380px_1fr]">
        <SubmitForm
          configs={configs}
          onSubmitted={(job) => {
            setJobs(prev => [job, ...prev]);
            setSelected(job.id);
          }}
        />

        <div>
          <Card>
            <CardHeader className="flex flex-row items-center justify-between border-b pb-3">
              <CardTitle className="text-base">Jobs</CardTitle>
              <span className="text-xs text-muted-foreground">auto-refreshes every 3s</span>
            </CardHeader>
            <CardContent className="p-0">
              {jobs.length === 0 ? (
                <div className="p-8 text-center text-sm text-muted-foreground">
                  No jobs yet. Submit one to get started.
                </div>
              ) : (
                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-left text-xs uppercase tracking-wider text-muted-foreground">
                      <Th>ID</Th><Th>Game</Th><Th>Engine</Th><Th>Status</Th><Th>Worker</Th><Th>Created</Th>
                    </tr>
                  </thead>
                  <tbody>
                    {jobs.map(j => (
                      <JobRow key={j.id} job={j} selected={j.id === selectedId} onSelect={setSelected} />
                    ))}
                  </tbody>
                </table>
              )}
            </CardContent>
          </Card>

          {selectedJob && <ResultsPanel job={selectedJob} />}
        </div>
      </div>
    </div>
  );
}

const Th = ({ children }) => <th className="border-b border-border/60 px-3 py-2 font-semibold">{children}</th>;
const Td = ({ children }) => <td className="border-b border-border/40 px-3 py-2.5">{children}</td>;

function JobRow({ job, selected, onSelect }) {
  const created = job.created_at?.slice(0, 19).replace("T", " ");
  const engine  = job.config?.exeConfig;
  return (
    <tr
      onClick={() => onSelect(job.id)}
      className={"cursor-pointer transition-colors hover:bg-accent/30 " + (selected ? "bg-accent/40" : "")}
    >
      <Td><code className="text-xs text-muted-foreground">{job.id.slice(0, 8)}…</code></Td>
      <Td>{job.game_name}</Td>
      <Td><Badge tone={engine ?? "generic"}>{ENGINE_LABEL[engine] ?? engine ?? "—"}</Badge></Td>
      <Td><Badge tone={job.status}>{job.status}</Badge></Td>
      <Td><span className="text-xs text-muted-foreground">{job.worker_id ?? "—"}</span></Td>
      <Td><span className="text-xs text-muted-foreground">{created}</span></Td>
    </tr>
  );
}

// ─── SubmitForm ─────────────────────────────────────────────────────────────

function SubmitForm({ onSubmitted, configs }) {
  const [name, setName] = useState("");
  const [args, setArgs] = useState("");
  const [file, setFile]         = useState(null);
  const [duration, setDuration] = useState(60);
  const [executable, setExec]   = useState("");
  const [exeConfig, setExe]     = useState("generic");
  const [mock, setMock]         = useState(false);
  const [loading, setLoading]   = useState(false);
  const [error, setError]       = useState(null);

  function applyPreset(id) {
    const p = configs.find(c => c.id === id)?.config;
    if (!p) return;
    if (p.exeConfig)        setExe(p.exeConfig);
    if (p.duration_seconds) setDuration(p.duration_seconds);
    if (p.executable)       setExec(p.executable);
  }

  async function handleSubmit(e) {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      const parsedArgs = args.trim() ? args.trim().split(/\s+/) : [];
      const config = JSON.stringify({
        duration_seconds: Number(duration),
        executable, exeConfig, mock,
        args: parsedArgs, resolution: "1920x1080", quality_preset: "high"
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

      const { data: job } = await axios.post("/api/jobs", fd, {
        headers: { "Content-Type": "multipart/form-data" }
      });
      onSubmitted(job);
      setName(""); setArgs(""); setFile(null); setDuration(60); setExec(""); setExe("generic"); setMock(false);
    } catch (err) {
      setError(err.response?.data?.error ?? err.message);
    } finally {
      setLoading(false);
    }
  }

  return (
    <Card>
      <CardHeader><CardTitle className="text-base">Submit Benchmark Job</CardTitle></CardHeader>
      <CardContent>
        <form onSubmit={handleSubmit} onKeyDown={(e) => { if (e.key === "Enter") e.preventDefault(); }} className="flex flex-col gap-4">
          {configs.length > 0 && (
            <div>
              <Label>Load preset</Label>
              <select
                className="mt-1 flex h-10 w-full rounded-md border border-input bg-background px-3 text-sm"
                defaultValue=""
                onChange={e => applyPreset(e.target.value)}
              >
                <option value="">— choose a preset —</option>
                {configs.map(c => <option key={c.id} value={c.id}>{c.name ?? c.id.slice(0, 8)}</option>)}
              </select>
            </div>
          )}

          <label className="flex cursor-pointer items-center gap-2 text-sm text-muted-foreground">
            <input type="checkbox" checked={mock} onChange={e => setMock(e.target.checked)} className="h-4 w-4 accent-primary" />
            Mock run <span className="text-xs">(simulate — no real game needed)</span>
          </label>

          <div>
            <Label>Engine</Label>
            <select
              className="mt-1 flex h-10 w-full rounded-md border border-input bg-background px-3 text-sm"
              value={exeConfig}
              onChange={e => setExe(e.target.value)}
            >
              <option value="generic">Generic</option>
              <option value="unreal">Unreal Engine</option>
              <option value="unity">Unity</option>
            </select>
          </div>

          <div>
            <Label>Game name</Label>
            <Input className="mt-1" value={name} onChange={e => setName(e.target.value)} placeholder={mock ? "mock-run" : "My Game v1.2"} />
          </div>

        <div>
            <Label>Args</Label>
            <Input className="mt-1" value={args} onChange={e => setArgs(e.target.value)} placeholder={mock ? "mock-run" : ""} />
        </div>

          {!mock && (
            <>
              <div>
                <Label>Game file <span className="text-xs">(.zip, .tar.gz, executable)</span></Label>
                <Input className="mt-1" type="file" onChange={e => setFile(e.target.files[0])} />
              </div>
              <div>
                <Label>Executable path <span className="text-xs">(relative inside archive)</span></Label>
                <Input className="mt-1" value={executable} onChange={e => setExec(e.target.value)}
                  placeholder={exeConfig === "unreal" ? "Binaries/Win64/MyGame.exe" : "bin/game.exe"} />
              </div>
            </>
          )}

          <div>
            <Label>Duration: <strong className="text-foreground">{duration}s</strong></Label>
            <input type="range" min={5} max={300} step={5} value={duration}
              onChange={e => setDuration(e.target.value)}
              className="mt-2 w-full accent-primary" />
          </div>

          {error && (
            <div className="rounded-md border border-destructive/40 bg-destructive/15 px-3 py-2 text-sm text-destructive">
              {error}
            </div>
          )}

          <Button type="submit" disabled={loading}>{loading ? "Submitting…" : "Submit Job"}</Button>
        </form>
      </CardContent>
    </Card>
  );
}

// ─── SavePresetDialog ───────────────────────────────────────────────────────

function SavePresetDialog({ onSaved }) {
  const [open, setOpen]         = useState(false);
  const [name, setName]         = useState("");
  const [exeConfig, setExe]     = useState("generic");
  const [duration, setDuration] = useState(60);
  const [executable, setExecP]  = useState("");
  const [saving, setSaving]     = useState(false);

  async function save(e) {
    e.preventDefault();
    setSaving(true);
    try {
      await axios.post("/jsonapi/configs", {
        data: { type: "config", attributes: { name, config: { exeConfig, duration_seconds: duration, executable } } }
      }, { headers: { "Content-Type": "application/vnd.api+json" } });
      onSaved?.();
      setOpen(false);
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="outline" size="sm"><Plus className="mr-1 h-4 w-4" /> Save preset</Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader><DialogTitle>Save Config Preset</DialogTitle></DialogHeader>
        <form onSubmit={save} className="flex flex-col gap-3">
          <div><Label>Preset name</Label><Input required value={name} onChange={e => setName(e.target.value)} placeholder="UE5 High 1080p" /></div>
          <div>
            <Label>Engine</Label>
            <select className="flex h-10 w-full rounded-md border border-input bg-background px-3 text-sm" value={exeConfig} onChange={e => setExe(e.target.value)}>
              <option value="generic">Generic</option><option value="unreal">Unreal Engine</option><option value="unity">Unity</option>
            </select>
          </div>
          <div><Label>Default duration (s)</Label><Input type="number" min={5} max={300} value={duration} onChange={e => setDuration(Number(e.target.value))} /></div>
          <div><Label>Default executable path</Label><Input value={executable} onChange={e => setExecP(e.target.value)} placeholder="Binaries/Win64/MyGame.exe" /></div>
          <div className="flex justify-end gap-2 pt-2">
            <DialogClose asChild><Button type="button" variant="ghost">Cancel</Button></DialogClose>
            <Button type="submit" disabled={saving}>{saving ? "Saving…" : "Save preset"}</Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}

// ─── ResultsPanel ───────────────────────────────────────────────────────────

function ResultsPanel({ job }) {
  const res     = job.results;
  const metrics = res?.metrics;
  const fps     = res?.fps;
  const ue      = res?.unreal;
  const engine  = job.config?.exeConfig;

  return (
    <Card className="mt-5">
      <CardHeader>
        <div className="flex flex-wrap items-center gap-3">
          <CardTitle className="text-base">Job Details</CardTitle>
          <Badge tone={job.status}>{job.status}</Badge>
          <Badge tone={engine ?? "generic"}>{ENGINE_LABEL[engine] ?? engine ?? "—"}</Badge>
        </div>
      </CardHeader>
      <CardContent>
        <div className="mb-4 grid grid-cols-2 gap-2 text-sm">
          <Kv k="ID" v={<code className="text-xs">{job.id}</code>} />
          <Kv k="Game" v={job.game_name} />
          <Kv k="Worker" v={job.worker_id ?? "—"} />
          <Kv k="Created" v={job.created_at?.slice(0, 19).replace("T", " ")} />
        </div>

        {job.status === "failed" && (
          <div className="rounded-md border border-destructive/40 bg-destructive/15 px-3 py-2 text-sm text-destructive">
            {job.error ?? "Unknown error"}
          </div>
        )}
        {(job.status === "pending" || job.status === "running") && (
          <div className="text-sm text-muted-foreground">Waiting for results…</div>
        )}

        {ue && (
          <div className="mt-3">
            <SectionLabel>Unreal Thread Times (ms)</SectionLabel>
            <div className="grid grid-cols-3 gap-2">
              <Metric label="Game Thread"   value={`${ue.game_thread_ms?.avg} ms`}   sub={`p95 ${ue.game_thread_ms?.p95} ms`} />
              <Metric label="Render Thread" value={`${ue.render_thread_ms?.avg} ms`} sub={`p95 ${ue.render_thread_ms?.p95} ms`} />
              <Metric label="GPU"           value={`${ue.gpu_ms?.avg} ms`}           sub={`p95 ${ue.gpu_ms?.p95} ms`} />
            </div>
          </div>
        )}

        {fps && (
          <div className="mt-3">
            <SectionLabel>FPS</SectionLabel>
            <div className="grid grid-cols-4 gap-2">
              <Metric label="Avg"   value={fps.avg} />
              <Metric label="Min"   value={fps.min} />
              <Metric label="Max"   value={fps.max} />
              <Metric label="1% Low" value={fps.p1_low} />
            </div>
          </div>
        )}

        {metrics && (
          <div className="mt-3">
            <SectionLabel>System</SectionLabel>
            <div className="grid grid-cols-3 gap-2">
              <Metric label="CPU avg" value={`${metrics.cpu_percent?.avg}%`} />
              <Metric label="CPU p95" value={`${metrics.cpu_percent?.p95}%`} />
              <Metric label="Mem avg" value={`${metrics.memory_mb?.avg} MB`} />
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

const SectionLabel = ({ children }) => (
  <div className="mb-2 text-xs font-semibold uppercase tracking-wider text-muted-foreground">{children}</div>
);
const Metric = ({ label, value, sub }) => (
  <div className="rounded-md bg-secondary px-3 py-2">
    <div className="text-xs uppercase tracking-wider text-muted-foreground">{label}</div>
    <div className="text-lg font-bold">{value ?? "—"}</div>
    {sub && <div className="text-xs text-muted-foreground">{sub}</div>}
  </div>
);
const Kv = ({ k, v }) => (
  <div><span className="text-muted-foreground">{k}: </span><span className="text-foreground">{v}</span></div>
);
