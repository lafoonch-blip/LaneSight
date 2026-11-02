// DEC-125 §4: create a `lanesight-queue` GitHub issue from a founder-APPROVED insight. The issue carries
// the approved spec ONLY — never raw feedback text (prompt-injection defense: the build agent works from the
// spec, not from user-submitted feedback). Server-only: GITHUB_TOKEN is read from the environment and must
// never reach the client bundle, so this module is imported only by the "use server" actions.
const REPO = process.env.LANESIGHT_QUEUE_REPO ?? "lafoonch-blip/LaneSight";

export interface QueueIssueInput {
  id: string;
  title: string;
  type: string;
  summary: string;
  proposed_change: string | null;
  affected_area: string | null;
  priority: string | null;
  related_decs: string[];
  feedback_count: number;
  bowler_count: number;
  phases: string[];
}

export function githubConfigured(): boolean {
  return Boolean(process.env.GITHUB_TOKEN);
}

export async function createQueueIssue(ins: QueueIssueInput): Promise<number> {
  const token = process.env.GITHUB_TOKEN;
  if (!token) throw new Error("GITHUB_TOKEN not set");

  const body = [
    `**Type:** ${ins.type}`,
    `**Priority:** ${ins.priority ?? "—"}`,
    `**Affected area:** ${ins.affected_area ?? "—"}`,
    ins.related_decs.length ? `**Related DECs:** ${ins.related_decs.join(", ")}` : null,
    "",
    "## Summary",
    ins.summary,
    "",
    "## Proposed change",
    ins.proposed_change ?? "—",
    "",
    "## Evidence",
    `${ins.feedback_count} feedback item(s) from ${ins.bowler_count} bowler(s); phases: ${ins.phases.join(", ") || "—"}.`,
    "",
    "---",
    `Founder-approved from Feedback Insights (DEC-125). Insight id: \`${ins.id}\`. Raw feedback text is deliberately omitted — the build agent works only from this approved spec.`,
  ]
    .filter((l): l is string => l !== null)
    .join("\n");

  const labels = ["lanesight-queue", `type:${ins.type}`];
  if (ins.priority) labels.push(`priority:${ins.priority}`);

  const resp = await fetch(`https://api.github.com/repos/${REPO}/issues`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ title: `[queue] ${ins.title}`, body, labels }),
  });
  if (!resp.ok) {
    throw new Error(`GitHub ${resp.status}: ${(await resp.text()).slice(0, 300)}`);
  }
  const json = (await resp.json()) as { number: number };
  return json.number;
}
