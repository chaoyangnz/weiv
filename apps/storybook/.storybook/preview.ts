import "../../../packages/ui-theme-default/src/tokens.css";
import "../../../packages/ui-theme-default/src/components.css";

import type { Preview } from "@storybook/html-vite";

const preview: Preview = {
  parameters: {
    docs: {
      codePanel: true,
    },
    options: {
      showPanel: true,
      panelPosition: "bottom",
    },
  },
  decorators: [
    story => {
      const wrapper = document.createElement("div");
      wrapper.setAttribute("data-theme", "default");
      wrapper.style.minHeight = "100vh";
      wrapper.style.padding = "24px";
      wrapper.style.boxSizing = "border-box";
      wrapper.append(story());
      return wrapper;
    },
  ],
};

export default preview;
