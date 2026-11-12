import { test } from "bun:test";

function runInspectInvalGraph(path: string): string {
  const proc = Bun.spawnSync({
    cmd: ["cyna-out/bin/weiv", "inspect", "invalidation-graph", path],
    stdout: "pipe",
    stderr: "pipe",
    cwd: process.cwd(),
  });

  if (proc.exitCode !== 0) {
    const stderr = new TextDecoder().decode(proc.stderr);
    throw new Error(`inspect invalidation-graph failed for ${path}\n${stderr}`);
  }

  return new TextDecoder().decode(proc.stdout);
}

test("kanib app inspect output exposes routed shell and callback ownership surfaces", () => {
  const output = runInspectInvalGraph("test/examples/kanib/App.weiv");

  if (!output.includes("invalidation-graph source=test/examples/kanib/App.weiv")) {
    throw new Error("Missing source banner for Kanib App inspect output");
  }
  if (!output.includes("name=WorkspaceShell deps=[shellState]")) {
    throw new Error("Missing WorkspaceShell dependency region in Kanib App inspect output");
  }
  if (!output.includes("name=WorkspaceSidebar deps=[shellState,workspaceShared]")) {
    throw new Error("Missing WorkspaceSidebar dependency region in Kanib App inspect output");
  }
  if (!output.includes("name=DetailPanel deps=[externalTicks,externalWatchRegistered,selectedIssue")) {
    throw new Error("Missing DetailPanel dependency region in Kanib App inspect output");
  }
  if (
    !output.includes(
      "callback callee=registerExternalSaveListener kind=inline_arrow owned_candidate=false reason=unknown_registration",
    )
  ) {
    throw new Error("Missing unowned callback registration diagnostics for external save listener");
  }
  if (!output.includes("child-event name=switch-workspace expr=switchWorkspace owned=true")) {
    throw new Error("Missing owned child-event boundary for workspace switching");
  }
  if (
    !output.includes("warning hidden-state expression=ensureRouter() reason=helper-contains-external-reads")
  ) {
    throw new Error("Missing ensureRouter hidden-state warning in Kanib App inspect output");
  }
});

test("kanib board inspect output exposes loop/conditional and action boundaries", () => {
  const output = runInspectInvalGraph("test/examples/kanib/views/IssueBoardPage.weiv");

  if (!output.includes("invalidation-graph source=test/examples/kanib/views/IssueBoardPage.weiv")) {
    throw new Error("Missing source banner for Kanib board inspect output");
  }
  if (
    !output.includes(
      "loop ref=2 name=column expr=columns() eval=direct deps=[columns,boardItems,listIssues,props,workspaceShared,listIssues(props.workspaceId, workspaceShared.selectedProjectId).filter]",
    )
  ) {
    throw new Error("Missing outer column loop dependency surface in Kanib board inspect output");
  }
  if (!output.includes("conditional ref=10 expr=column.items.length === 0 eval=direct deps=[column]")) {
    throw new Error("Missing conditional region for empty board columns");
  }
  if (!output.includes("loop ref=19 name=issue expr=column.items eval=direct deps=[column]")) {
    throw new Error("Missing inner issue loop dependency surface");
  }
  if (
    !output.includes("attribute ref=34 name=disabled expr=issue.status === 'done' eval=direct deps=[issue]")
  ) {
    throw new Error("Missing disabled attribute precision for status move controls");
  }
  if (!output.includes("template-event name=click expr=advanceIssue(issue.id) owned=true")) {
    throw new Error("Missing owned boundary for board advance action");
  }
  if (!output.includes("template-event name=click expr=moveToDone(issue.id) owned=true")) {
    throw new Error("Missing owned boundary for board move action");
  }
});
