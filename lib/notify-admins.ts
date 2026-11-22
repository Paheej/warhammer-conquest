/**
 * Fire-and-forget ping after a submission insert so admins get emailed
 * (throttled server-side to once a day — issue #54). keepalive lets the
 * request finish even though the form navigates away immediately. Never
 * throws: a failed email must not look like a failed submission.
 */
export function pingAdminsOfSubmission(): void {
  try {
    void fetch("/api/notify/submission", { method: "POST", keepalive: true }).catch(() => {});
  } catch {
    // ignore
  }
}
