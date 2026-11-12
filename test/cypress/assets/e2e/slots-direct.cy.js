describe("Slot composition direct bundle (reactive)", () => {
  beforeEach(() => {
    cy.visit("/");
    cy.get('[data-test="reactive"]').as("scope");
  });

  it("renders projected named-slot content", () => {
    cy.get("@scope").find('[data-test="header-title"]').should("have.text", "Initial");
    cy.get("@scope").find('[data-test="header-eyebrow"]').should("contain.text", "Updated 0");
  });

  it("renders projected default-slot content", () => {
    cy.get("@scope").find('[data-test="body"]').should("have.text", "Body 0");
  });

  it("updates projected slot interpolations when parent state changes", () => {
    cy.get("@scope")
      .find('[data-test="header-title"]')
      .then($el => {
        const before = $el[0];
        cy.get("@scope").find('[data-test="bump"]').click();
        cy.get("@scope").find('[data-test="header-title"]').should("have.text", "Bumped 1");
        cy.get("@scope")
          .find('[data-test="header-title"]')
          .then($after => {
            // Same element node — proves no remount
            expect($after[0]).to.equal(before);
          });
        cy.get("@scope").find('[data-test="body"]').should("have.text", "Body 1");
        cy.get("@scope").find('[data-test="header-eyebrow"]').should("contain.text", "Updated 1");
      });
  });

  it("updates non-slot interpolations in step with slot interpolations", () => {
    cy.get("@scope").find('[data-test="bump"]').click();
    cy.get("@scope").find('[data-test="bump"]').click();
    cy.get("@scope").find('[data-test="header-title"]').should("have.text", "Bumped 2");
    cy.get("@scope").find('[data-test="body"]').should("have.text", "Body 2");
    cy.get("@scope").find('[data-test="header-eyebrow"]').should("contain.text", "Updated 2");
  });
});

describe("Slot fallback content", () => {
  beforeEach(() => {
    cy.visit("/");
  });

  it("renders named-slot fallback when only the named slot is provided", () => {
    cy.get('[data-test="empty-with-named"]').within(() => {
      cy.contains("h2", "Hello").should("exist");
      // default slot was not provided — fallback message shows
      cy.contains(".empty-state__fallback-body", "No additional details.").should("exist");
    });
  });

  it("renders both fallbacks when no slots are provided", () => {
    cy.get('[data-test="empty-fallback"]').within(() => {
      cy.contains(".empty-state__fallback-message", "Nothing here yet.").should("exist");
      cy.contains(".empty-state__fallback-body", "No additional details.").should("exist");
    });
  });
});
