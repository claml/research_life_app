# 研LIFE Workbench Web Preview

## Local launch

From `front_app`, run:

```powershell
python -m http.server 8765 --bind 127.0.0.1
```

Open `http://127.0.0.1:8765/docs/workbench_preview/`.

## Acceptance paths

1. Today → Research → Notes → Weather → press `Escape`; Research and the Notes tab are restored.
2. Materials → select another file → Document View → Files; the selected file is preserved.
3. Collapse the sidebar → open Life → open Settings → expand the sidebar; compact state persists between workspaces.
4. Enable Reduced Transparency → open Weather; glass surfaces switch to opaque fallbacks.

## Keyboard behavior

- Use `Tab` and `Shift+Tab` to reach navigation, tabs, material selection buttons, and contextual controls. Focused controls have a visible ring.
- Use `Enter` or `Space` to activate a focused button.
- `Escape` exits only the Weather view and restores the preceding workspace and tab. It has no navigation effect elsewhere.
- The Search field is intentionally inert demo chrome; submitting it is prevented and does not reload the page.

## Viewport targets

- Desktop acceptance: `1280 × 800`.
- Compact acceptance: approximately `980px` wide. The sidebar uses compact mode, the Materials inspector may narrow or hide, and the file workflow remains usable without page-level horizontal overflow.

## Prototype limits

All content is fixed fictional demonstration data. The preview does not connect to a backend, filesystem, authentication, sync, AI, cloud service, or PDF processor, and it does not read personal data.

This static Web preview is a design-acceptance prototype. It is **not the Flutter application** and does not modify or replace the Flutter product.
