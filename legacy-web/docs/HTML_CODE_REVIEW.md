# HTML Code Review - Roguelike-like Project

**Review Date:** 2026-01-21
**Files Reviewed:** index.html, roguelikebutton.html, cache-test.html

## Executive Summary

The HTML code is functional but has several areas that need improvement for better maintainability, accessibility, and modern web standards compliance. The main issues are: extensive use of inline event handlers, missing accessibility features, and large file sizes.

---

## 1. index.html (748 lines)

### ✅ Strengths

1. **Proper HTML5 Structure**
   - Correct `<!DOCTYPE html>` declaration
   - Has `lang="en"` attribute on `<html>` tag (good for accessibility)
   - Proper `<meta charset="UTF-8">` and viewport meta tags

2. **External CSS**
   - Uses external stylesheet (css/styles.css) with cache-busting query string (?v=30)

3. **Script Loading**
   - Scripts loaded at bottom of body (good for performance)
   - Proper dependency order maintained

4. **Semantic Structure**
   - Some use of semantic elements like `<h1>`, `<h3>`, `<button>`

### ❌ Issues & Recommendations

#### **CRITICAL ISSUES**

1. **Inline Event Handlers** (index.html:15, 202, etc.)
   ```html
   <button onclick="showMapModal()">...</button>
   <button onclick="showLootModal()">...</button>
   ```
   - **Issue:** Violates Content Security Policy best practices
   - **Risk:** Makes code vulnerable to XSS attacks
   - **Fix:** Move all event handlers to external JavaScript files using `addEventListener()`

2. **Missing Accessibility Features**
   - **No ARIA labels** on interactive elements
   - **No alt text fallbacks** for empty alt attributes (line 68: `<img id="character-icon" src="" alt="Character">`)
   - **No focus management** for modal dialogs
   - **No keyboard navigation** support indicators
   - **Fix:** Add proper ARIA attributes, implement focus trapping in modals, add skip links

3. **Hidden Content without Semantic Markup** (line 243-247)
   ```html
   <div id="location-tooltip-data" style="display: none;">
   ```
   - **Issue:** Using inline styles to hide content
   - **Fix:** Use `hidden` attribute or CSS classes with `aria-hidden="true"`

#### **HIGH PRIORITY ISSUES**

4. **Inline Styles** (line 15, 172, 664, etc.)
   ```html
   <button style="margin-left: 10px; margin-right: 20px; display: none;">
   ```
   - **Issue:** Mixes presentation with structure
   - **Fix:** Move all styles to external CSS file

5. **Large SVG with Hardcoded Height** (line 174)
   ```html
   <svg id="connection-lines" style="position: absolute; top: 0; left: 0; width: 100%; height: 3000px; ...">
   ```
   - **Issue:** Fixed height of 3000px may cause layout issues
   - **Fix:** Use dynamic height calculation based on content

6. **Empty Divs as Containers** (lines 38-40, 209-211)
   ```html
   <div id="save-list">
     <!-- Save slots will be populated here -->
   </div>
   ```
   - **Issue:** No loading state or empty state markup
   - **Fix:** Add proper empty state messaging or loading indicators

7. **Button States Not Indicated** (line 661)
   ```html
   <button id="enableAutoLocationChange" style="background: #2196F3;">Enable Auto-Change</button>
   ```
   - **Issue:** Button state communicated only via inline color
   - **Fix:** Use classes and aria-pressed attribute for toggle buttons

#### **MEDIUM PRIORITY ISSUES**

8. **Inconsistent ID Naming Convention**
   - Mix of kebab-case (`new-game-btn`, `return-menu-top`) and camelCase (`toggleTutorial`, `itemSelect`)
   - **Fix:** Standardize on one convention (prefer kebab-case for HTML IDs)

9. **Missing Form Semantics** (line 335)
   ```html
   <input type="text" id="save-name-input" placeholder="Enter run name" ...>
   ```
   - **Issue:** Input has no associated `<label>` element
   - **Fix:** Add proper `<label>` tags or aria-label attributes

10. **Developer Tools in Production Build** (lines 428-670)
    - **Issue:** Large dev tools section included in production HTML
    - **Fix:** Conditionally include dev tools or move to separate HTML file

---

## 2. roguelikebutton.html (4,847 lines)

### ✅ Strengths

1. **Proper HTML5 Structure**
   - Correct DOCTYPE and meta tags
   - Has `lang="en"` attribute

### ❌ Issues & Recommendations

#### **CRITICAL ISSUES**

1. **Extremely Large File Size**
   - **Issue:** 4,847 lines is too large for a single HTML file
   - **Impact:** Slow loading, difficult maintenance, poor performance
   - **Fix:** Split into components or use a build system with templates

2. **All Styles Inline in `<style>` Tag**
   - **Issue:** ~500+ lines of CSS embedded in HTML (lines 7-500+)
   - **Fix:** Extract all CSS to external stylesheet(s)

3. **No External CSS File**
   - **Issue:** Unlike index.html, this file has no external CSS
   - **Fix:** Create external stylesheet and link it

#### **HIGH PRIORITY ISSUES**

4. **Duplicate CSS Rules**
   - Multiple definitions of similar styles (e.g., color classes for stats)
   - **Fix:** Consolidate and use CSS custom properties (CSS variables)

5. **Complex Inline Styles**
   - SVG manipulation via inline styles
   - **Fix:** Use CSS classes or JavaScript for dynamic styles

---

## 3. cache-test.html (106 lines)

### ✅ Strengths

1. **Clear Purpose**
   - Well-documented diagnostic tool
   - Helpful instructions for users

2. **Inline Styles Acceptable**
   - For a diagnostic tool, inline styles are acceptable

### ❌ Issues & Recommendations

#### **LOW PRIORITY ISSUES**

1. **Missing DOCTYPE on Line 1**
   - Actually, it does have DOCTYPE ✅

2. **No lang Attribute**
   - Actually, it's missing `lang="en"` on the `<html>` tag
   - **Fix:** Add `<html lang="en">`

---

## Overall Recommendations

### **Immediate Actions** (Critical)

1. ✅ **Remove all inline event handlers** from index.html
   - Replace with `addEventListener()` in external JS

2. ✅ **Add accessibility features**
   - ARIA labels for all interactive elements
   - Focus management for modals
   - Keyboard navigation support

3. ✅ **Refactor roguelikebutton.html**
   - Split into multiple files or use a template system
   - Extract all CSS to external files

### **Short-term Actions** (High Priority)

4. ✅ **Remove inline styles**
   - Move all `style="..."` attributes to CSS classes

5. ✅ **Standardize naming conventions**
   - Use consistent kebab-case for HTML IDs

6. ✅ **Add proper form labels**
   - Associate all inputs with labels

### **Long-term Actions** (Medium Priority)

7. ✅ **Consider a build system**
   - Use templating (Handlebars, EJS, etc.)
   - Implement component-based architecture

8. ✅ **Implement Content Security Policy**
   - Add CSP meta tag or headers
   - Remove all inline scripts/styles

9. ✅ **Optimize Performance**
   - Lazy load dev tools section
   - Minimize and bundle JavaScript files
   - Consider code splitting

---

## Accessibility Audit Summary

### **WCAG 2.1 Compliance Issues**

| Criterion | Level | Status | Issue |
|-----------|-------|--------|-------|
| 1.1.1 Non-text Content | A | ❌ Fail | Missing/empty alt text |
| 1.3.1 Info and Relationships | A | ❌ Fail | Missing form labels |
| 2.1.1 Keyboard | A | ⚠️ Partial | Modal focus management unclear |
| 2.4.3 Focus Order | A | ⚠️ Unknown | Needs testing |
| 3.2.4 Consistent Identification | AA | ❌ Fail | Inconsistent button patterns |
| 4.1.2 Name, Role, Value | A | ❌ Fail | Missing ARIA attributes |

### **Recommended Accessibility Fixes**

```html
<!-- BEFORE -->
<button onclick="showMapModal()">🗺️ Map</button>

<!-- AFTER -->
<button id="map-btn" aria-label="Open map view">
  <span aria-hidden="true">🗺️</span>
  Map
</button>

<!-- BEFORE -->
<div id="save-modal">
  <div class="flex gap-20">
    ...
  </div>
</div>

<!-- AFTER -->
<div id="save-modal" role="dialog" aria-modal="true" aria-labelledby="modal-title">
  <h2 id="modal-title">Start New Run</h2>
  <div class="flex gap-20">
    ...
  </div>
</div>
```

---

## Security Considerations

### **Current Vulnerabilities**

1. **XSS Risk via Inline Event Handlers**
   - Inline `onclick` attributes make CSP implementation difficult
   - Recommendation: Remove all inline event handlers

2. **No Content Security Policy**
   - Missing CSP headers or meta tags
   - Recommendation: Add CSP meta tag:
   ```html
   <meta http-equiv="Content-Security-Policy"
         content="default-src 'self'; script-src 'self'; style-src 'self';">
   ```

3. **Dynamic Content Insertion**
   - JavaScript files use innerHTML extensively (risk of XSS)
   - Recommendation: Audit all innerHTML usage, use textContent where possible

---

## Performance Considerations

### **Current Issues**

1. **Large HTML Files**
   - index.html: 748 lines (acceptable)
   - roguelikebutton.html: 4,847 lines (too large)

2. **No Resource Hints**
   - Missing preload/prefetch for critical resources
   - Recommendation: Add `<link rel="preload">` for critical CSS/JS

3. **Many Script Tags**
   - 20+ separate script files loaded
   - Recommendation: Bundle scripts in production build

4. **Cache-busting Query Strings**
   - Using ?v=XX on many resources (good!)
   - Ensure versioning is consistent across deploys

---

## Browser Compatibility

### **Potential Issues**

1. **SVG with Fixed Height**
   - May not render correctly on all screen sizes
   - Test on mobile devices

2. **CSS Grid Usage** (if present in CSS file)
   - Check support for older browsers
   - Consider fallbacks for IE11 if needed

3. **ES6 Module Usage**
   - Check if JavaScript uses ES6 modules
   - May need transpilation for older browsers

---

## Conclusion

The HTML structure is functional but needs modernization for better maintainability, accessibility, and security. Priority should be given to:

1. Removing inline event handlers
2. Adding proper accessibility features
3. Refactoring roguelikebutton.html into smaller components
4. Moving inline styles to external CSS

**Estimated Refactoring Effort:**
- Critical issues: 16-24 hours
- High priority: 8-16 hours
- Medium priority: 8-12 hours

**Total: 32-52 hours of development time**

---

## Next Steps

1. Review this document with the development team
2. Prioritize fixes based on impact and effort
3. Create tickets for each major refactoring task
4. Implement fixes incrementally to avoid breaking changes
5. Add automated testing for accessibility (e.g., axe-core, Lighthouse)
