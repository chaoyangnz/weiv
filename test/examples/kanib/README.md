# Kanib

This app should replace the current loose "workspace demo" with a clearer,
Kaneo-inspired product shape.

Reference product direction:

- Kaneo: <https://github.com/usekaneo/kaneo>

We are not cloning Kaneo feature-for-feature. We are borrowing the product
shape:

- lightweight project / issue management
- workspace-centric navigation
- issue list + board + detail flows
- clear, believable collaboration surfaces

The goal is to make `test/examples/kanib` feel like a small real
product while still acting as the flagship `weiv` verification app.

## Product Story

The app should feel like a focused team workspace for tracking work:

- choose a workspace
- review issue health
- browse issues as a list or board
- inspect and update one issue in detail
- manage members and settings

It should read as:

- understandable to a human
- plausible as a product
- broad enough to stress the framework

Not:

- a fake dashboard made only of cards
- a routing demo with no product logic
- an enterprise admin panel full of unrelated widgets

## Route Shape

The replacement app should explicitly cover the runtime router.

Recommended route structure:

1. `/`
- initial landing or redirect into the current workspace

2. `/workspaces/:workspaceId`
- workspace overview
- health metrics
- recent activity
- assigned items

3. `/workspaces/:workspaceId/issues`
- issue list view
- filters, search, status chips
- empty and loading states

4. `/workspaces/:workspaceId/board`
- grouped board view of the same issues
- denser conditional and repeated subtrees

5. `/workspaces/:workspaceId/issues/:issueId`
- issue detail
- metadata sidebar
- activity/comments section
- async save/update flow

6. `/workspaces/:workspaceId/members`
- team member list
- roles
- invitation or management actions

7. `/workspaces/:workspaceId/settings`
- workspace preferences
- forms
- toggles and destructive confirmations

These routes should be real runtime routes, not just tab state pretending to be
routes.

## Coverage Intent

This app should cover roughly `80-90%` of meaningful `weiv` product-surface
behavior, while dedicated fixtures continue to cover the sharp edges.

It should intentionally exercise:

- nested component composition
- props across several boundaries
- router matching and route params
- nested routes and shared layout preservation
- local state
- one bounded shared observable area
- list and board views over the same data
- issue detail rendering
- conditionals and loops
- helper-derived display
- async event handlers
- owned callback mutation
- one conservative/unowned callback example
- slot/default/named/fallback projection
- scoped CSS density across many components
- app bundle generation
- component tests and bundle tests

## Slot Strategy

Slots should feel native to the product, not like a separate showcase page.

Use them in these components:

### `WorkspaceShell`

Named slots:

- `header`
- `toolbar`
- default content
- `aside`

Why:

- shared routed layout
- nested route preservation
- believable shell composition

### `Panel`

Named slots:

- `title`
- `actions`
- default content
- `footer`

Why:

- repeated across overview, issue detail, activity, members, settings
- good repeated product-level projection surface

### `EmptyState`

Named slots:

- `icon`
- `title`
- default body
- `actions`

Why:

- natural place for fallback slot coverage
- appears in issues, board columns, members, notifications

### `DetailPanel`

Named slots:

- `title`
- `actions`
- default content

Why:

- product-grade issue-detail composition
- nested slot usage inside a real workflow

Dedicated slot fixtures in `test/examples/slots` should still remain. The app
should prove believable slot usage, not absorb every slot corner case.

## Component Shape

The app now follows a frontend-style layout with routable pages under
`views/` and reusable pieces under `components/`:

- `App.weiv`
- `components/WorkspaceShell.weiv`
- `components/WorkspaceHeader.weiv`
- `components/WorkspaceSidebar.weiv`
- `components/Panel.weiv`
- `components/EmptyState.weiv`
- `components/MetricGrid.weiv`
- `components/MetricCard.weiv`
- `components/DetailPanel.weiv`
- `components/DetailSection.weiv`
- `components/ActivityItem.weiv`
- `views/OverviewPage.weiv`
- `views/IssueListPage.weiv`
- `views/IssueBoardPage.weiv`
- `views/IssueDetailPage.weiv`
- `views/MembersPage.weiv`
- `views/SettingsPage.weiv`
- `state/workspace.ts`
- `utils/format.ts`
- `utils/metric_tone.js`

This layout should clearly separate:

- routed pages
- reusable shell surfaces
- repeated issue/list/board pieces
- bounded shared state

## Data Model

Use mocked in-memory product data.

No real backend is required. If async behavior is needed, simulate it with:

- delayed promises
- queued callbacks
- mocked mutation helpers

Recommended data areas:

- workspaces
- projects or issue groups
- issues
- assignees
- comments/activity entries
- member list
- settings/preferences
- notifications or inbox badges

Keep it rich enough to feel like a product, but small enough to debug locally.

## Shared State Boundary

The app should keep most state local.

Use `observable()` from `@weiv/runtime` only for a bounded cross-route/shared
area such as:

- current workspace selection
- global notification badge state
- one issue presence/status summary shared between shell and page

Avoid turning the whole app into shared-state-first architecture.

## Verification Expectations

The replacement app should become the main flagship verification app for:

- `cyna test .`
- `npm run test:component`
- future browser e2e smoke paths

Compiler-side checks should cover:

- route-bearing component build-through
- app bundle emission
- invalidation-graph usefulness on a denser routed app
- component analysis usefulness on representative pages

Runtime/component tests should cover:

- route navigation
- view switching without full root replacement
- issue list filtering
- issue detail updates
- slot-based shell/panel rendering
- shared observable updates

## Replacement Goal

This app should replace the current unclear release-readiness workspace story.

The new standard is:

- Kaneo-inspired
- routed
- issue/workspace-centric
- human-readable
- product-like
- broad enough to be the main `weiv` integration test base
