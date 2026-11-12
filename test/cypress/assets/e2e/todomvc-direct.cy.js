describe("TodoMVC direct bundle", () => {
  beforeEach(() => {
    cy.visit("/");
  });

  function clickFilter(name) {
    cy.contains(".filters button", name).click();
  }

  function toggleTodo(label, checked) {
    const toggle = cy.contains(".todo-list li label", label).parents("li").find(".toggle");
    if (checked) {
      toggle.check({ force: true });
    } else {
      toggle.uncheck({ force: true });
    }
  }

  it("shows a newly completed item in the Completed filter", () => {
    cy.contains(".filters button", "All").click();
    cy.contains(".todo-list li label", "Verify root-owned state updates across nested components")
      .parents("li")
      .find(".toggle")
      .check({ force: true });

    cy.contains(".filters button", "Completed").click();
    cy.contains(".todo-list li label", "Verify root-owned state updates across nested components").should(
      "exist",
    );
  });

  it("keeps checkboxes clickable after All -> Completed -> All", () => {
    cy.contains(".filters button", "Completed").click();
    cy.contains(".filters button", "All").click();

    cy.contains(".todo-list li label", "Keep scoped CSS realistic under a larger tree")
      .parents("li")
      .as("targetItem");

    cy.get("@targetItem").find(".toggle").check({ force: true });
    cy.get("@targetItem").should("have.class", "completed");

    cy.contains(".filters button", "Completed").click();
    cy.contains(".todo-list li label", "Keep scoped CSS realistic under a larger tree").should("exist");
  });

  it("toggles correctly inside the Active and Completed filters", () => {
    clickFilter("Active");
    toggleTodo("Verify root-owned state updates across nested components", true);
    cy.contains(".todo-list li label", "Verify root-owned state updates across nested components").should(
      "not.exist",
    );

    clickFilter("Completed");
    toggleTodo("Verify root-owned state updates across nested components", false);
    cy.contains(".todo-list li label", "Verify root-owned state updates across nested components").should(
      "not.exist",
    );

    clickFilter("Active");
    cy.contains(".todo-list li label", "Verify root-owned state updates across nested components").should(
      "exist",
    );
  });

  it("survives repeated filter switching and on/off toggles", () => {
    const label = "Keep scoped CSS realistic under a larger tree";

    clickFilter("All");
    toggleTodo(label, true);
    clickFilter("Completed");
    cy.contains(".todo-list li label", label).should("exist");

    clickFilter("All");
    toggleTodo(label, false);
    clickFilter("Active");
    cy.contains(".todo-list li label", label).should("exist");

    clickFilter("Completed");
    cy.contains(".todo-list li label", label).should("not.exist");

    clickFilter("All");
    toggleTodo(label, true);
    clickFilter("Completed");
    cy.contains(".todo-list li label", label).should("exist");

    clickFilter("All");
    toggleTodo(label, false);
    clickFilter("Active");
    cy.contains(".todo-list li label", label).should("exist");

    clickFilter("All");
    cy.contains(".todo-list li label", label).parents("li").should("not.have.class", "completed");
  });

  it("creates, filters, edits, toggles, and clears todos", () => {
    cy.get(".newtodo").type("Cypress direct path{enter}");
    cy.get(".todo-list li").first().should("contain.text", "Cypress direct path");

    cy.contains(".filters button", "Active").click();
    cy.get(".todo-list li").should("not.contain.text", "Port TodoMVC into the verification suite");

    cy.contains(".todo-list label", "Exercise edit, filter, and clear-completed flows").dblclick();
    cy.get(".edit")
      .should("have.value", "Exercise edit, filter, and clear-completed flows")
      .clear()
      .type("Cypress edited flow{enter}");
    cy.contains(".todo-list label", "Cypress edited flow").should("exist");

    cy.get(".todo-list .toggle").first().check({ force: true });
    cy.contains(".todo-list label", "Cypress direct path").should("not.exist");

    cy.contains(".filters button", "All").click();
    cy.contains(".clear-completed", "Clear completed").click();

    cy.contains(".todo-list label", "Port TodoMVC into the verification suite").should("not.exist");
    cy.contains(".todo-list label", "Expose the polished preview on the LAN server").should("not.exist");
    cy.contains(".todo-list label", "Cypress direct path").should("not.exist");
    cy.contains(".todo-list label", "Cypress edited flow").should("exist");
  });

  it("toggles all items on and off", () => {
    cy.get(".toggle-all").check({ force: true });
    cy.get(".todo-list li").each($item => {
      cy.wrap($item).should("have.class", "completed");
    });
    cy.contains(".todo-count strong", "0").should("exist");

    clickFilter("Completed");
    cy.get(".todo-list li").should("have.length.at.least", 1);

    clickFilter("All");
    cy.get(".toggle-all").uncheck({ force: true });
    cy.get(".todo-list li").each($item => {
      cy.wrap($item).should("not.have.class", "completed");
    });
    cy.contains(".todo-count strong", "5").should("exist");
  });

  it("cancels edit on Escape without changing the item", () => {
    const original = "Exercise edit, filter, and clear-completed flows";

    cy.contains(".todo-list label", original).dblclick();
    cy.get(".edit").should("have.value", original).clear().type("Escape should not save{esc}");

    cy.get(".edit").should("not.exist");
    cy.contains(".todo-list label", original).should("exist");
    cy.contains(".todo-list label", "Escape should not save").should("not.exist");
  });

  it("saves edit on blur", () => {
    cy.contains(".todo-list label", "Keep scoped CSS realistic under a larger tree").dblclick();
    cy.get(".edit").clear().type("Blur saved todo").blur();

    cy.get(".edit").should("not.exist");
    cy.contains(".todo-list label", "Blur saved todo").should("exist");
  });
});
