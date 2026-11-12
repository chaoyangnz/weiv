import { observable } from "weiv:observable";

export type WorkspaceSummary = {
  id: string;
  name: string;
  key: string;
  issueCount: number;
  openCount: number;
};

export type WorkspaceMetric = {
  id: string;
  label: string;
  value: string;
  change: number;
};

export type WorkspaceProject = {
  id: string;
  workspaceId: string;
  name: string;
  key: string;
};

export type WorkspaceIssue = {
  id: string;
  workspaceId: string;
  projectId: string;
  title: string;
  summary: string;
  detail: string;
  owner: string;
  status: "backlog" | "in-progress" | "review" | "done";
  priority: "low" | "medium" | "high";
  updatedMinutesAgo: number;
  watchers: number;
};

export type WorkspaceMember = {
  id: string;
  workspaceId: string;
  name: string;
  role: string;
  focus: string;
};

export type IssueComment = {
  id: string;
  issueId: string;
  workspaceId: string;
  author: string;
  body: string;
  minutesAgo: number;
};

export type NotificationItem = {
  id: string;
  workspaceId: string;
  title: string;
  detail: string;
  issueId: string | null;
  read: boolean;
  minutesAgo: number;
};

export interface WorkspaceSharedState {
  currentWorkspaceId: string;
  selectedProjectId: string;
  selectedIssueId: string;
  notifications: number;
  saveTick: number;
  currentPath: string;
  externalSaveTick: number;
}

export const workspaceShared: WorkspaceSharedState = observable({
  currentWorkspaceId: "compiler-lab",
  selectedProjectId: "proj-core-runtime",
  selectedIssueId: "iss-102",
  notifications: 4,
  saveTick: 0,
  currentPath: "/workspaces/compiler-lab",
  externalSaveTick: 0,
});

type RouterLike = {
  push(path: string): void | Promise<void>;
  replace(path: string): void | Promise<void>;
};

const workspaceCatalog: WorkspaceSummary[] = [
  { id: "compiler-lab", name: "Compiler Lab", key: "CL", issueCount: 4, openCount: 3 },
  { id: "design-systems", name: "Design Systems", key: "DS", issueCount: 2, openCount: 2 },
];

const workspaceMetrics: Record<string, WorkspaceMetric[]> = {
  "compiler-lab": [
    { id: "m-1", label: "Open issues", value: "3", change: -1 },
    { id: "m-2", label: "Review queue", value: "1", change: -2 },
    { id: "m-3", label: "Cycle time", value: "3.4d", change: -6 },
  ],
  "design-systems": [
    { id: "m-4", label: "Open issues", value: "2", change: 1 },
    { id: "m-5", label: "Review queue", value: "1", change: 0 },
    { id: "m-6", label: "Cycle time", value: "2.8d", change: -3 },
  ],
};

const projects: WorkspaceProject[] = [
  { id: "proj-core-runtime", workspaceId: "compiler-lab", name: "Core Runtime", key: "CR" },
  { id: "proj-devx", workspaceId: "compiler-lab", name: "Developer Experience", key: "DX" },
  { id: "proj-ui-kit", workspaceId: "design-systems", name: "UI Kit", key: "UI" },
  { id: "proj-theme-engine", workspaceId: "design-systems", name: "Theme Engine", key: "TH" },
];

export const issues: WorkspaceIssue[] = observable([
  {
    id: "iss-101",
    workspaceId: "compiler-lab",
    projectId: "proj-core-runtime",
    title: "Fix router state mismatch after history back",
    summary: "Returning from issue detail occasionally restores stale workspace path metadata.",
    detail:
      "Reproduce history back/forward transitions and make route-derived shell state consistent before and after popstate handlers execute.",
    owner: "Avery",
    status: "in-progress",
    priority: "high",
    updatedMinutesAgo: 18,
    watchers: 3,
  },
  {
    id: "iss-102",
    workspaceId: "compiler-lab",
    projectId: "proj-devx",
    title: "Ship inspect snapshot test harness",
    summary: "Promote invalidation inspect output to a stable CLI contract test suite.",
    detail:
      "Add Bun snapshot tests for app-scale inspect output and define update workflow so compiler shape changes are intentionally reviewed.",
    owner: "Mika",
    status: "review",
    priority: "high",
    updatedMinutesAgo: 44,
    watchers: 5,
  },
  {
    id: "iss-103",
    workspaceId: "compiler-lab",
    projectId: "proj-devx",
    title: "Tighten diagnostics JSON contract",
    summary: "Editor integration needs a stable machine-readable diagnostics envelope.",
    detail:
      "Unify severity fields across parse/bind/emit and add contract tests for lint-style output consumed by editor tooling.",
    owner: "Noa",
    status: "backlog",
    priority: "medium",
    updatedMinutesAgo: 91,
    watchers: 2,
  },
  {
    id: "iss-104",
    workspaceId: "compiler-lab",
    projectId: "proj-core-runtime",
    title: "Audit slot usage in flagship app",
    summary: "Ensure layout slots read as product composition, not framework demos.",
    detail:
      "Track named/default/fallback slot behavior across routed shell regions and confirm projected content updates under selective invalidation.",
    owner: "Lina",
    status: "done",
    priority: "low",
    updatedMinutesAgo: 160,
    watchers: 1,
  },
  {
    id: "iss-201",
    workspaceId: "design-systems",
    projectId: "proj-ui-kit",
    title: "Define token-ready shell spacing scale",
    summary: "Current shell spacing values drift between sidebar, panels, and detail surfaces.",
    detail:
      "Publish a compact spacing scale and refactor key components to consume shared tokenized spacing variables.",
    owner: "Sana",
    status: "review",
    priority: "medium",
    updatedMinutesAgo: 36,
    watchers: 4,
  },
  {
    id: "iss-202",
    workspaceId: "design-systems",
    projectId: "proj-theme-engine",
    title: "Theme empty states for light + high-contrast",
    summary: "Fallback states need stronger contrast and hierarchy for accessibility review.",
    detail:
      "Add high-contrast compliant token variants for empty state borders, body copy, and action affordances while preserving the default theme.",
    owner: "Theo",
    status: "in-progress",
    priority: "low",
    updatedMinutesAgo: 72,
    watchers: 2,
  },
]);

const members: WorkspaceMember[] = [
  { id: "mem-1", workspaceId: "compiler-lab", name: "Avery", role: "Staff Engineer", focus: "Runtime" },
  { id: "mem-2", workspaceId: "compiler-lab", name: "Mika", role: "Product Engineer", focus: "App examples" },
  { id: "mem-3", workspaceId: "compiler-lab", name: "Noa", role: "DX Engineer", focus: "Diagnostics" },
  {
    id: "mem-4",
    workspaceId: "design-systems",
    name: "Sana",
    role: "Design Engineer",
    focus: "Shell patterns",
  },
  { id: "mem-5", workspaceId: "design-systems", name: "Theo", role: "Frontend Engineer", focus: "States" },
];

export const comments: IssueComment[] = observable([
  {
    id: "cmt-1",
    issueId: "iss-101",
    workspaceId: "compiler-lab",
    author: "Avery",
    body: "History mismatch reproduces after opening detail from board and navigating back twice.",
    minutesAgo: 42,
  },
  {
    id: "cmt-2",
    issueId: "iss-102",
    workspaceId: "compiler-lab",
    author: "Mika",
    body: "Snapshot test naming should mirror inspect command grouping.",
    minutesAgo: 64,
  },
  {
    id: "cmt-3",
    issueId: "iss-201",
    workspaceId: "design-systems",
    author: "Sana",
    body: "Spacing token proposals are ready for review in Figma branch v2.",
    minutesAgo: 21,
  },
]);

export const notificationItems: NotificationItem[] = observable([
  {
    id: "ntf-1",
    workspaceId: "compiler-lab",
    title: "Review requested on inspect harness",
    detail: "Mika requested review on iss-102",
    issueId: "iss-102",
    read: false,
    minutesAgo: 8,
  },
  {
    id: "ntf-2",
    workspaceId: "compiler-lab",
    title: "Router bug status changed",
    detail: "Avery moved iss-101 to in-progress",
    issueId: "iss-101",
    read: false,
    minutesAgo: 17,
  },
  {
    id: "ntf-3",
    workspaceId: "compiler-lab",
    title: "Diagnostics contract review requested",
    detail: "Noa requested review on iss-103",
    issueId: "iss-103",
    read: false,
    minutesAgo: 25,
  },
  {
    id: "ntf-4",
    workspaceId: "compiler-lab",
    title: "Slot audit marked done",
    detail: "Lina closed iss-104",
    issueId: "iss-104",
    read: false,
    minutesAgo: 39,
  },
  {
    id: "ntf-5",
    workspaceId: "design-systems",
    title: "Token scale draft published",
    detail: "Sana updated iss-201 with spacing draft notes",
    issueId: "iss-201",
    read: false,
    minutesAgo: 12,
  },
  {
    id: "ntf-6",
    workspaceId: "design-systems",
    title: "Contrast variant merged",
    detail: "Theo pushed theme updates for iss-202",
    issueId: "iss-202",
    read: true,
    minutesAgo: 54,
  },
]);

const externalSaveListeners: Array<() => void> = [];
let activeRouter: RouterLike | null = null;

function syncNotificationCount() {
  workspaceShared.notifications = notificationItems.filter(
    item => item.workspaceId === workspaceShared.currentWorkspaceId && !item.read,
  ).length;
}

syncNotificationCount();

export function listWorkspaces() {
  return workspaceCatalog;
}

export function listMetrics(workspaceId: string) {
  return workspaceMetrics[workspaceId] || [];
}

export function listProjects(workspaceId: string) {
  return projects.filter(project => project.workspaceId === workspaceId);
}

export function listIssues(workspaceId: string, projectId?: string) {
  if (projectId) {
    return issues.filter(issue => issue.workspaceId === workspaceId && issue.projectId === projectId);
  }
  return issues.filter(issue => issue.workspaceId === workspaceId);
}

export function listMembers(workspaceId: string) {
  return members.filter(member => member.workspaceId === workspaceId);
}

export function listComments(issueId: string) {
  return comments.filter(comment => comment.issueId === issueId);
}

export function listNotifications(workspaceId: string) {
  return notificationItems.filter(item => item.workspaceId === workspaceId);
}

export function findWorkspace(workspaceId: string) {
  return workspaceCatalog.find(workspace => workspace.id === workspaceId) || workspaceCatalog[0];
}

export function findProject(projectId: string) {
  return projects.find(project => project.id === projectId) || null;
}

export function findIssue(issueId: string) {
  return issues.find(issue => issue.id === issueId) || null;
}

export function setCurrentWorkspaceId(workspaceId: string) {
  workspaceShared.currentWorkspaceId = workspaceId;
  const workspaceProjects = listProjects(workspaceId);
  workspaceShared.selectedProjectId = workspaceProjects[0]?.id ?? "";
  syncNotificationCount();
}

export function setSelectedProjectId(projectId: string) {
  workspaceShared.selectedProjectId = projectId;
}

export function setSelectedIssueId(issueId: string) {
  workspaceShared.selectedIssueId = issueId;
}

export function clearNotifications() {
  for (const item of notificationItems) {
    if (item.workspaceId === workspaceShared.currentWorkspaceId) {
      item.read = true;
    }
  }
  syncNotificationCount();
  workspaceShared.saveTick += 1;
}

export function bumpNotifications() {
  const issue = findIssue(workspaceShared.selectedIssueId);
  const workspaceId = issue ? issue.workspaceId : workspaceShared.currentWorkspaceId;
  notificationItems.unshift({
    id: `ntf-${notificationItems.length + 1}`,
    workspaceId,
    title: "New update available",
    detail: issue ? `${issue.owner} updated ${issue.id}` : "Workspace activity refreshed",
    issueId: issue ? issue.id : null,
    read: false,
    minutesAgo: 0,
  });
  syncNotificationCount();
  workspaceShared.saveTick += 1;
}

export function addComment(issueId: string, author: string, body: string) {
  const issue = findIssue(issueId);
  if (!issue) return;
  comments.unshift({
    id: `cmt-${comments.length + 1}`,
    issueId,
    workspaceId: issue.workspaceId,
    author,
    body,
    minutesAgo: 0,
  });
  notificationItems.unshift({
    id: `ntf-${notificationItems.length + 1}`,
    workspaceId: issue.workspaceId,
    title: `New comment on ${issue.id}`,
    detail: `${author}: ${body}`,
    issueId,
    read: false,
    minutesAgo: 0,
  });
  syncNotificationCount();
  workspaceShared.saveTick += 1;
}

export function markNotificationRead(notificationId: string) {
  const item = notificationItems.find(entry => entry.id === notificationId);
  if (!item || item.read) return;
  item.read = true;
  syncNotificationCount();
  workspaceShared.saveTick += 1;
}

export function registerExternalSaveListener(listener: () => void) {
  externalSaveListeners.push(listener);
}

export function emitExternalSavePulse() {
  workspaceShared.externalSaveTick += 1;
  for (const listener of externalSaveListeners) {
    listener();
  }
}

export function cycleIssueStatus(issueId: string) {
  const issue = findIssue(issueId);
  if (!issue) return;

  const nextStatus =
    issue.status === "backlog"
      ? "in-progress"
      : issue.status === "in-progress"
        ? "review"
        : issue.status === "review"
          ? "done"
          : "backlog";

  issue.status = nextStatus;
  issue.updatedMinutesAgo = 0;
  issue.watchers += 1;
  workspaceShared.saveTick += 1;
}

export function moveIssueToStatus(issueId: string, status: "backlog" | "in-progress" | "review" | "done") {
  const issue = findIssue(issueId);
  if (!issue) return;
  if (issue.status === status) return;
  issue.status = status;
  issue.updatedMinutesAgo = 0;
  issue.watchers += 1;
  workspaceShared.saveTick += 1;
}

export function setWorkspaceRouter(router: RouterLike) {
  activeRouter = router;
}

export function syncRouteState(path: string, workspaceId?: string, issueId?: string) {
  workspaceShared.currentPath = path;
  if (workspaceId) {
    workspaceShared.currentWorkspaceId = workspaceId;
    const workspaceProjects = listProjects(workspaceId);
    const hasSelectedProject = workspaceProjects.some(
      project => project.id === workspaceShared.selectedProjectId,
    );
    if (!hasSelectedProject) {
      workspaceShared.selectedProjectId = workspaceProjects[0]?.id ?? "";
    }
    syncNotificationCount();
  }
  if (issueId) {
    workspaceShared.selectedIssueId = issueId;
    const issue = findIssue(issueId);
    if (issue && issue.workspaceId === workspaceShared.currentWorkspaceId) {
      workspaceShared.selectedProjectId = issue.projectId;
    }
    return;
  }

  const workspaceIssues = listIssues(workspaceShared.currentWorkspaceId, workspaceShared.selectedProjectId);
  if (workspaceIssues.length > 0) {
    workspaceShared.selectedIssueId = workspaceIssues[0].id;
  }
}

export function navigateTo(path: string) {
  activeRouter?.push(path);
}

export function replaceWith(path: string) {
  activeRouter?.replace(path);
}

export function workspaceRoute(workspaceId: string) {
  return `/workspaces/${workspaceId}`;
}

export function issuesRoute(workspaceId: string) {
  return `/workspaces/${workspaceId}/issues`;
}

export function boardRoute(workspaceId: string) {
  return `/workspaces/${workspaceId}/board`;
}

export function issueRoute(workspaceId: string, issueId: string) {
  return `/workspaces/${workspaceId}/issues/${issueId}`;
}

export function notificationsRoute(workspaceId: string) {
  return `/workspaces/${workspaceId}/notifications`;
}

export function membersRoute(workspaceId: string) {
  return `/workspaces/${workspaceId}/members`;
}

export function settingsRoute(workspaceId: string) {
  return `/workspaces/${workspaceId}/settings`;
}
