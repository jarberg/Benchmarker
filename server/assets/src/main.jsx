import "./app.css";
import React from "react";
import { createRoot } from "react-dom/client";
import { createInertiaApp } from "@inertiajs/react";
import axios from "axios";

// Phoenix CSRF token wiring for axios (used by the multipart upload).
const csrf = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content");
if (csrf) axios.defaults.headers.common["x-csrf-token"] = csrf;

createInertiaApp({
  resolve: (name) => {
    const pages = import.meta.glob("./pages/**/*.jsx", { eager: true });
    return pages[`./pages/${name}.jsx`];
  },
  setup({ el, App, props }) {
    createRoot(el).render(<App {...props} />);
  }
});
