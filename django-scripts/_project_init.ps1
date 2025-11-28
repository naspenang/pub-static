# NOTE:
# This script is safe to re-run: it only creates files if they are missing,
# and does NOT overwrite website/views.py, website/urls.py, or VS Code configs.

Write-Host ""
Write-Host "=== Django Initial Setup ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "THIS PROJECT WILL TAKE THE PARENT FOLDER NAME AS PROJECT NAME" -ForegroundColor Cyan
Write-Host ""
Write-Host "Detecting project name from folder..." -ForegroundColor Cyan

# Get raw folder name
$folderName = Split-Path -Leaf (Get-Location).Path

function Get-SafeProjectName {
    param(
        [string]$Name
    )

    # trim + lower
    $n = $Name.Trim().ToLowerInvariant()

    # replace spaces and hyphens with underscores
    $n = $n -replace '[\s\-]+', '_'

    # remove anything that's not letter/number/underscore
    $n = $n -replace '[^a-z0-9_]', ''

    # make sure it starts with a letter or underscore
    if ($n -notmatch '^[a-z_][a-z0-9_]*$') {
        $n = "project_$n"
    }

    # if somehow empty, fall back
    if ([string]::IsNullOrWhiteSpace($n)) {
        $n = "project"
    }

    return $n
}

$projectName = Get-SafeProjectName $folderName

Write-Host "Folder name: $folderName" -ForegroundColor Cyan
Write-Host "Using Django project name: $projectName" -ForegroundColor Cyan
Write-Host ""

# Track created/skipped files for summary
$created = @()
$skipped = @()

# -------------------------------------------------
# 0. Create requirements.txt (plain text) if missing
# -------------------------------------------------
$requirementsPath = ".\requirements.txt"

if (-not (Test-Path $requirementsPath)) {
    Write-Host ""
    Write-Host "Creating default requirements.txt..." -ForegroundColor Yellow

    $requirementsText = @"
asgiref==3.11.0
certifi==2025.11.12
cffi==2.0.0
charset-normalizer==3.4.4
cryptography==46.0.3
defusedxml==0.7.1
Django==5.2.8
django-environ==0.12.0
django-htmx==1.26.0
idna==3.11
oauthlib==3.3.1
pycparser==2.23
PyJWT==2.10.1
python3-openid==3.2.0
requests==2.32.5
requests-oauthlib==2.0.0
social-auth-app-django==5.6.0
social-auth-core==4.8.1
sqlparse==0.5.3
tzdata==2025.2
urllib3==2.5.0
"@

    $requirementsText | Set-Content $requirementsPath -Encoding utf8
    Write-Host "requirements.txt created." -ForegroundColor Green
    $created += "requirements.txt"
}
else {
    Write-Host ""
    Write-Host "requirements.txt already exists. Using existing file." -ForegroundColor Yellow
    $skipped += "requirements.txt"
}

# -------------------------------------------------
# 0.1 Create _setup.blank (Python helper) if missing
# -------------------------------------------------
$setupBlankPath = ".\_setup.blank"

if (-not (Test-Path $setupBlankPath)) {
    Write-Host ""
    Write-Host "Creating _setup.blank..." -ForegroundColor Yellow

    $setupBlankContent = @'
import os
import sys
import re
from collections import defaultdict

# -----------------------------
#  PATHS & APP INFO
# -----------------------------
APP_DIR = os.path.dirname(os.path.abspath(__file__))
APP_NAME = os.path.basename(APP_DIR)

VIEW_FILE = os.path.join(APP_DIR, "views.py")
URLS_FILE = os.path.join(APP_DIR, "urls.py")
TEMPLATES_DIR = os.path.join(APP_DIR, "templates", APP_NAME)
NAV_FILE = os.path.join(TEMPLATES_DIR, "nav.html")
BASE_TEMPLATE = os.path.join(TEMPLATES_DIR, "base.html")
FOOTER_FILE = os.path.join(TEMPLATES_DIR, "footer.html")


# Pages that cannot be deleted or renamed
PROTECTED_PAGES = {"home", "nav", "footer", "sidebar"}


# -----------------------------
#  COLOURS (for CLI)
# -----------------------------
RESET = "\033[0m"
BOLD = "\033[1m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
RED = "\033[91m"
CYAN = "\033[96m"


def c(text, colour):
    return f"{colour}{text}{RESET}"


# -----------------------------
#  PAGE NAME HELPERS (support subfolders like 'reports/monthly')
# -----------------------------
def normalise_page_id(raw: str) -> str:
    """Clean user input like ' //Reports//Monthly/ ' → 'reports/monthly'."""
    raw = raw.strip().strip("/").lower()
    raw = re.sub(r"/+", "/", raw)
    return raw


def valid_page_id(page_id: str) -> bool:
    """
    Check that each segment in 'reports/monthly' is valid:
    letters/numbers/underscore, starts with a letter.
    """
    if not page_id:
        return False
    parts = page_id.split("/")
    return all(re.match(r"^[a-zA-Z][a-zA-Z0-9_]*$", p) for p in parts)


def view_name_from_page(page_id: str) -> str:
    """'reports/monthly' → 'reports_monthly' (for Python function name)."""
    return page_id.replace("/", "_")


def url_path_from_page(page_id: str) -> str:
    """'reports/monthly_report' → 'reports/monthly-report' (for URL path)."""
    return "/".join(part.replace("_", "-") for part in page_id.split("/"))


# -----------------------------
#  HELPERS
# -----------------------------
def valid_page_name(name: str) -> bool:
    """Only allow: letters, numbers, underscore. Must start with a letter."""
    return bool(re.match(r"^[a-zA-Z][a-zA-Z0-9_]*$", name))


def ensure_views_file():
    """Ensure views.py exists and imports render."""
    if not os.path.exists(VIEW_FILE):
        with open(VIEW_FILE, "w") as f:
            f.write("from django.shortcuts import render\n")
        print(c("✔ Created views.py", GREEN))

    with open(VIEW_FILE, "r") as f:
        content = f.read()

    if "from django.shortcuts import render" not in content:
        with open(VIEW_FILE, "w") as f:
            f.write("from django.shortcuts import render\n\n" + content)
        print(c("✔ Added 'render' import to views.py", GREEN))


def strip_bom(filepath):
    """Remove UTF-8 BOM (U+FEFF) if present in a file."""
    if not os.path.exists(filepath):
        return

    # utf-8-sig will read and automatically drop BOM if it exists
    with open(filepath, "r", encoding="utf-8-sig") as f:
        data = f.read()

    # write it back as normal UTF-8 with no BOM
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(data)


def ensure_urls_file():
    """Ensure urls.py exists, is clean (no BOM), and contains 'from . import views'."""
    # If file doesn't exist, create a clean one
    if not os.path.exists(URLS_FILE):
        with open(URLS_FILE, "w", encoding="utf-8") as f:
            f.write(
                "from django.urls import path\n"
                "from . import views\n\n"
                "urlpatterns = [\n"
                "]\n"
            )
        print("✔ Created urls.py")
        return

    # Clean BOM if some editor or copy-paste added it
    strip_bom(URLS_FILE)

    # Now work with the cleaned file
    with open(URLS_FILE, "r", encoding="utf-8") as f:
        lines = f.readlines()

    if not any(line.strip() == "from . import views" for line in lines):
        for i, line in enumerate(lines):
            if line.startswith("from django.urls"):
                lines.insert(i + 1, "from . import views\n")
                break
        else:
            lines.insert(0, "from . import views\n")

        with open(URLS_FILE, "w", encoding="utf-8") as f:
            f.writelines(lines)

        print("✔ Added 'from . import views' to urls.py")


def ensure_nav_template():
    """Create templates/<app>/nav.html if missing."""
    os.makedirs(TEMPLATES_DIR, exist_ok=True)

    if os.path.exists(NAV_FILE):
        return

    with open(NAV_FILE, "w") as f:
        f.write(
            "{% load static %}\n"
            '<nav class="navbar navbar-expand-lg navbar-dark bg-dark mb-4">\n'
            '  <div class="container-fluid">\n'
            '  <a class="navbar-brand" href="/">'
            f'<img src="{{% static \'images/logo.png\' %}}" style="height: 40px; margin-top: -5px" />'
            f"    {APP_NAME.title()}"
            "    </a>"
            '    <button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="#mainNav">\n'
            '      <span class="navbar-toggler-icon"></span>\n'
            "    </button>\n"
            '    <div class="collapse navbar-collapse" id="mainNav">\n'
            '      <ul class="navbar-nav ms-auto mb-2 mb-lg-0">\n'
            "        <!-- AUTO-GENERATED NAV START -->\n"
            "        <!-- items will be injected by menu.py -->\n"
            "        <!-- AUTO-GENERATED NAV END -->\n"
            "      </ul>\n"
            "    </div>\n"
            "  </div>\n"
            "</nav>\n"
        )

    print(c(f"✔ Created nav template: {NAV_FILE}", GREEN))


def ensure_footer_template():
    """Create templates/<app>/footer.html if missing."""
    os.makedirs(TEMPLATES_DIR, exist_ok=True)

    if os.path.exists(FOOTER_FILE):
        return

    with open(FOOTER_FILE, "w") as f:
        f.write(
            '<footer class="bg-dark text-white text-center py-3 mt-5">\n'
            '  <div class="container">\n'
            "    <small>&copy; 2025 Your Project Name. All rights reserved.</small>\n"
            "  </div>\n"
            "</footer>\n"
        )

    print(c(f"✔ Created footer template: {FOOTER_FILE}", GREEN))


def ensure_base_template():
    """
    Create templates/<app>/base.html if missing and make sure it includes nav.html and footer.html.
    """
    os.makedirs(TEMPLATES_DIR, exist_ok=True)

    # Always ensure nav + footer exist first
    ensure_nav_template()
    ensure_footer_template()

    include_nav_double = f'{{% include "{APP_NAME}/nav.html" %}}'
    include_nav_single = f"{{% include '{APP_NAME}/nav.html' %}}"

    include_footer_double = f'{{% include "{APP_NAME}/footer.html" %}}'
    include_footer_single = f"{{% include '{APP_NAME}/footer.html' %}}"

    if not os.path.exists(BASE_TEMPLATE):
        # brand new base.html using nav + footer include
        with open(BASE_TEMPLATE, "w") as f:
            f.write(
                "<!DOCTYPE html>\n"
                "<html lang='en'>\n"
                "<head>\n"
                "    <meta charset='utf-8'>\n"
                "    <meta name='viewport' content='width=device-width, initial-scale=1'>\n"
                f"    <title>{{% block title %}}{APP_NAME.title()}{{% endblock %}}</title>\n"
                "    <link href='https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css' rel='stylesheet'>\n"
                "</head>\n"
                "<body class='bg-light'>\n"
                f'    {{% include "{APP_NAME}/nav.html" %}}\n'
                "    <div class='container my-4'>\n"
                "        {% block content %}{% endblock %}\n"
                "    </div>\n"
                f'    {{% include "{APP_NAME}/footer.html" %}}\n'
                "    <script src='https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js'></script>\n"
                "</body>\n"
                "</html>\n"
            )

        print(c(f"✔ Created base template: {BASE_TEMPLATE}", GREEN))
        return

    # If base.html already exists, ensure it has both includes
    with open(BASE_TEMPLATE, "r") as f:
        content = f.read()

    nav_present = include_nav_double in content or include_nav_single in content
    footer_present = (
        include_footer_double in content or include_footer_single in content
    )

    lines = content.splitlines(keepends=True)
    changed = False

    if not nav_present:
        include_line = f'    {{% include "{APP_NAME}/nav.html" %}}\n'
        inserted = False

        for i, line in enumerate(lines):
            if "<body" in line:
                lines.insert(i + 1, include_line)
                inserted = True
                break

        if not inserted:
            lines.insert(0, include_line)

        changed = True
        print(c("✔ Updated base.html to include nav.html", GREEN))

    if not footer_present:
        footer_line = f'    {{% include "{APP_NAME}/footer.html" %}}\n'
        inserted = False

        # Try to insert before closing </body> or before the JS script
        for i, line in enumerate(lines):
            if "bootstrap.bundle.min.js" in line or "</body>" in line:
                lines.insert(i, footer_line)
                inserted = True
                break

        if not inserted:
            lines.append(footer_line)

        changed = True
        print(c("✔ Updated base.html to include footer.html", GREEN))

    if changed:
        with open(BASE_TEMPLATE, "w") as f:
            f.writelines(lines)


# -----------------------------
#  CREATE PAGE (INLINE)
# -----------------------------
def create_view(page_name: str):
    ensure_views_file()

    with open(VIEW_FILE, "r") as f:
        content = f.read()

    view_name = view_name_from_page(page_name)
    func_def = f"def {view_name}(request):"

    if func_def in content:
        print(c(f"⚠ View '{view_name}()' already exists. Skipping.", YELLOW))
        return

    template_ref = f"'{APP_NAME}/{page_name}.html'"

    with open(VIEW_FILE, "a") as f:
        f.write(
            f"\n\n"
            f"def {view_name}(request):\n"
            f"    return render(request, {template_ref})\n"
        )

    print(c(f"✔ Added view function '{view_name}()' to views.py", GREEN))


def create_template(page_name: str):
    ensure_base_template()

    path = os.path.join(TEMPLATES_DIR, f"{page_name}.html")
    os.makedirs(os.path.dirname(path), exist_ok=True)

    if os.path.exists(path):
        print(c(f"⚠ Template '{page_name}.html' already exists. Skipping.", YELLOW))
        return

    last_part = page_name.split("/")[-1]
    nice_title = last_part.replace("_", " ").title()

    with open(path, "w") as f:
        f.write(
            "{% extends '" + APP_NAME + "/base.html' %}\n\n"
            "{% block title %}"
            + nice_title
            + " | "
            + APP_NAME.title()
            + "{% endblock %}\n\n"
            "{% block content %}\n"
            f"    <h1>{nice_title}</h1>\n"
            "    <p>This page was generated automatically by <code>menu.py</code>.</p>\n"
            "{% endblock %}\n"
        )

    print(c(f"✔ Created template: {path}", GREEN))


def create_url(page_name: str):
    strip_bom(URLS_FILE)
    ensure_urls_file()

    view_name = view_name_from_page(page_name)
    url_path = url_path_from_page(page_name)

    with open(URLS_FILE, "r") as f:
        lines = f.readlines()

    new_route = f"    path('{url_path}/', views.{view_name}, name='{view_name}'),\n"

    if any(new_route.strip() == line.strip() for line in lines):
        print(c(f"⚠ URL for '{page_name}' already exists. Skipping.", YELLOW))
        return

    for i, line in enumerate(lines):
        if line.strip() == "]":
            lines.insert(i, new_route)
            break

    with open(URLS_FILE, "w") as f:
        f.writelines(lines)

    print(c(f"✔ Added URL route for '{page_name}' → /{url_path}/", GREEN))


# -----------------------------
#  DELETE PAGE (INLINE)
# -----------------------------
def delete_view(page_name: str):
    if not os.path.exists(VIEW_FILE):
        print(
            c(f"⚠ views.py not found, skipping view removal for '{page_name}'.", YELLOW)
        )
        return

    with open(VIEW_FILE, "r") as f:
        lines = f.readlines()

    view_name = view_name_from_page(page_name)
    func_pattern = f"def {view_name}(request):"
    start_idx = None

    for i, line in enumerate(lines):
        if line.strip().startswith(func_pattern):
            start_idx = i
            break

    if start_idx is None:
        print(c(f"⚠ View function '{view_name}()' not found in views.py.", YELLOW))
        return

    end_idx = start_idx + 1
    while end_idx < len(lines):
        stripped = lines[end_idx].lstrip()
        if stripped.startswith("def ") and not stripped.startswith(func_pattern):
            break
        end_idx += 1

    while end_idx < len(lines) and lines[end_idx].strip() == "":
        end_idx += 1

    del lines[start_idx:end_idx]

    with open(VIEW_FILE, "w") as f:
        f.writelines(lines)

    print(c(f"✔ Removed view function '{view_name}()' from views.py", GREEN))


def delete_template(page_name: str):
    path = os.path.join(TEMPLATES_DIR, f"{page_name}.html")

    if not os.path.exists(path):
        print(c(f"⚠ Template '{page_name}.html' not found, skipping.", YELLOW))
        return

    os.remove(path)
    print(c(f"✔ Deleted template: {path}", GREEN))


def delete_url(page_name: str):
    strip_bom(URLS_FILE)
    if not os.path.exists(URLS_FILE):
        print(
            c(f"⚠ urls.py not found, skipping URL removal for '{page_name}'.", YELLOW)
        )
        return

    with open(URLS_FILE, "r") as f:
        lines = f.readlines()

    view_name = view_name_from_page(page_name)
    url_path = url_path_from_page(page_name)
    new_lines = []
    removed = False

    for line in lines:
        if (
            f"views.{view_name}" in line
            or f"name='{view_name}'" in line
            or f"'{url_path}/'" in line
        ):
            removed = True
            continue
        new_lines.append(line)

    if not removed:
        print(c(f"⚠ No URL route found for '{page_name}' in urls.py.", YELLOW))
    else:
        with open(URLS_FILE, "w") as f:
            f.writelines(new_lines)
        print(c(f"✔ Removed URL route for '{page_name}' from urls.py", GREEN))


# -----------------------------
#  PAGE LISTING
# -----------------------------
def get_pages():
    """Return list of page ids like 'page1' or 'reports/monthly'."""
    if not os.path.exists(TEMPLATES_DIR):
        return []

    pages = []

    for root, _, files in os.walk(TEMPLATES_DIR):
        for f in files:
            if not f.endswith(".html"):
                continue
            if f in {"base.html", "nav.html"}:
                continue

            full_path = os.path.join(root, f)
            rel_path = os.path.relpath(
                full_path, TEMPLATES_DIR
            )  # e.g. 'reports/monthly.html'
            rel_no_ext = rel_path[:-5]  # remove '.html'
            page_id = rel_no_ext.replace(os.sep, "/")

            if page_id not in PROTECTED_PAGES:
                pages.append(page_id)

    return sorted(pages)


def list_pages():
    """Print all page templates, then wait for user input."""
    pages = get_pages()

    if not pages:
        print(c("⚠ No page templates found (only maybe base.html).", YELLOW))
        input(c("\nPress any key to return to menu...", CYAN))
        return

    print(f"\n{c('Pages in app', CYAN)} {c(APP_NAME, BOLD)}:\n")
    for i, p in enumerate(pages, start=1):
        print(f" {c(i, CYAN)}. {p}")

    input(c("\nPress any key to continue...", CYAN))


# -----------------------------
#  NAVIGATION UPDATER
# -----------------------------
def update_navigation():
    """
    Update the navigation links in nav.html based on existing pages.

    Grouping (folder-based):
      - 'reports' root page → top-level or first item in dropdown
      - 'reports/monthly', 'reports/summary' → dropdown items under Reports
      - simple pages ('about') → top-level links
    """
    pages = get_pages()

    if not os.path.exists(NAV_FILE):
        print(c("⚠ nav.html not found, navigation not updated.", YELLOW))
        return

    def title_from(s):
        return s.replace("_", " ").title()

    singles = set()
    grouped = defaultdict(list)

    for page in pages:
        parts = page.split("/")
        if len(parts) == 1:
            singles.add(page)
        else:
            prefix = parts[0]
            grouped[prefix].append(page)

    handled = set()

    lines = []
    lines.append("        <!-- AUTO-GENERATED NAV START -->\n")

    # Dropdowns for grouped pages
    for prefix in sorted(grouped.keys()):
        group_pages = sorted(grouped[prefix])
        handled.update(group_pages)

        has_root = prefix in singles
        if has_root:
            handled.add(prefix)
            singles.discard(prefix)

        lines.append('        <li class="nav-item dropdown">\n')
        lines.append(
            f'          <a class="nav-link dropdown-toggle" href="#" role="button" '
            f'data-bs-toggle="dropdown" aria-expanded="false">{title_from(prefix)}</a>\n'
        )
        lines.append('          <ul class="dropdown-menu dropdown-menu-end">\n')

        # Root page /prefix/
        if has_root:
            slug = url_path_from_page(prefix)
            label = title_from(prefix)
            lines.append(
                f'            <li><a class="dropdown-item" href="/{slug}/">{label}</a></li>\n'
            )

        # Child pages /prefix/.../
        for p in group_pages:
            if p == prefix:
                continue
            slug = url_path_from_page(p)
            suffix = p.split("/")[-1]
            label = title_from(suffix)
            lines.append(
                f'            <li><a class="dropdown-item" href="/{slug}/">{label}</a></li>\n'
            )

        lines.append("          </ul>\n")
        lines.append("        </li>\n")

    # Simple pages (no folder)
    for page in sorted(pages):
        if page in handled:
            continue
        slug = url_path_from_page(page)
        label = title_from(page.split("/")[-1])
        lines.append(
            f'        <li class="nav-item"><a class="nav-link" href="/{slug}/">{label}</a></li>\n'
        )

    lines.append("        <!-- AUTO-GENERATED NAV END -->\n")

    nav_block = "".join(lines)

    with open(NAV_FILE, "r") as f:
        content = f.read()

    start_tag = "<!-- AUTO-GENERATED NAV START -->"
    end_tag = "<!-- AUTO-GENERATED NAV END -->"

    if start_tag in content and end_tag in content:
        start_idx = content.index(start_tag)
        end_idx = content.index(end_tag) + len(end_tag)
        new_content = content[:start_idx] + nav_block + content[end_idx:]
    else:
        split_lines = content.splitlines(keepends=True)
        inserted = False
        for i, line in enumerate(split_lines):
            if "navbar-nav" in line and "<ul" in line:
                split_lines.insert(i + 1, nav_block)
                inserted = True
                break
        if not inserted:
            split_lines.append("\n" + nav_block)
        new_content = "".join(split_lines)

    with open(NAV_FILE, "w") as f:
        f.write(new_content)

    print(c("✔ Navigation in nav.html updated.", GREEN))


# -----------------------------
#  MENU ACTIONS
# -----------------------------
def run_createpages():
    """Ask for page names and create them (view + template + URL)."""
    names = input("Enter page name(s) to CREATE (space-separated): ").strip()
    if not names:
        print(c("No names entered, cancelled.\n", YELLOW))
        return

    raw_names = names.split()
    pages = []
    seen = set()

    for name in raw_names:
        page_id = normalise_page_id(name)
        if not valid_page_id(page_id):
            print(
                c(
                    f"❌ Invalid page name '{name}'. Use letters, numbers, underscores and '/'.",
                    RED,
                )
            )
            continue
        if page_id not in seen:
            seen.add(page_id)
            pages.append(page_id)

    if not pages:
        print(c("No valid page names. Cancelled.\n", YELLOW))
        return

    print(f"\nCreating pages in app {c(APP_NAME, BOLD)}: {', '.join(pages)}\n")

    for page in pages:
        print(c(f"=== {page} ===", CYAN))
        create_view(page)
        create_template(page)
        create_url(page)
        print()

    update_navigation()
    print(c("🎉 All selected pages created successfully!\n", GREEN))


def run_deletepages():
    """Show numbered list of pages, allow name/number/range input, then delete."""
    pages = get_pages()
    if not pages:
        print(c("⚠ No pages available to delete.", YELLOW))
        return

    print(f"\n{c('Pages in', CYAN)} {c(APP_NAME, BOLD)}:\n")
    for i, p in enumerate(pages, start=1):
        print(f" {c(i, CYAN)}. {p}")
    print()

    raw = input(
        "Enter page NAME(S), NUMBER(S), or RANGE(S) to delete (e.g. '2 5 home 3-4'):\n> "
    ).strip()

    if not raw:
        print(c("No input provided, cancelled.\n", YELLOW))
        return

    tokens = raw.split()
    selected = []
    seen = set()

    for item in tokens:
        if re.match(r"^\d+-\d+$", item):
            start_str, end_str = item.split("-")
            start = int(start_str)
            end = int(end_str)
            if start > end:
                start, end = end, start
            for n in range(start, end + 1):
                idx = n - 1
                if 0 <= idx < len(pages):
                    name = pages[idx]
                    if name not in seen:
                        seen.add(name)
                        selected.append(name)
                else:
                    print(c(f"⚠ Number '{n}' is out of range, skipping.", YELLOW))
        elif item.isdigit():
            idx = int(item) - 1
            if 0 <= idx < len(pages):
                name = pages[idx]
                if name not in seen:
                    seen.add(name)
                    selected.append(name)
            else:
                print(c(f"⚠ Number '{item}' is out of range, skipping.", YELLOW))
        else:
            name = item.lower()
            if name in pages and name not in seen:
                seen.add(name)
                selected.append(name)
            elif name not in pages:
                print(c(f"⚠ Page '{name}' not found, skipping.", YELLOW))

    if not selected:
        print(c("No valid pages selected. Cancelled.\n", YELLOW))
        return

    selected = [p for p in selected if p not in PROTECTED_PAGES]

    if not selected:
        print(c("🚫 Selected pages are protected and cannot be deleted.", RED))
        return

    print("\nYou are about to delete these pages:")
    for p in selected:
        print(" -", c(p, RED))

    confirm = input(c("Are you sure? (y/N): ", YELLOW)).strip().lower()
    if confirm not in ("y", "yes"):
        print(c("Deletion cancelled.\n", YELLOW))
        return

    for page_name in selected:
        print(c(f"\n=== Deleting page: {page_name} ===", CYAN))
        delete_view(page_name)
        delete_template(page_name)
        delete_url(page_name)

    update_navigation()
    print(c("\n🗑️  Done deleting requested pages.\n", GREEN))


# -----------------------------
#  RENAME PAGE
# -----------------------------
def rename_in_views(old: str, new: str):
    if not os.path.exists(VIEW_FILE):
        print(c("⚠ views.py not found, skipping views rename.", YELLOW))
        return

    with open(VIEW_FILE, "r") as f:
        content = f.read()

    old_def = f"def {view_name_from_page(old)}(request):"
    new_def = f"def {view_name_from_page(new)}(request):"

    if old_def not in content:
        print(c(f"⚠ View '{old}()' not found in views.py.", YELLOW))
        return

    content = content.replace(old_def, new_def)

    old_tpl = f"'{APP_NAME}/{old}.html'"
    new_tpl = f"'{APP_NAME}/{new}.html'"
    content = content.replace(old_tpl, new_tpl)

    with open(VIEW_FILE, "w") as f:
        f.write(content)

    print(c(f"✔ Renamed view '{old}' → '{new}' in views.py", GREEN))


def rename_in_template(old: str, new: str):
    old_path = os.path.join(TEMPLATES_DIR, f"{old}.html")
    new_path = os.path.join(TEMPLATES_DIR, f"{new}.html")

    if not os.path.exists(old_path):
        print(c(f"⚠ Template '{old}.html' not found, skipping.", YELLOW))
        return

    if os.path.exists(new_path):
        print(c(f"⚠ Template '{new}.html' already exists, not overwriting.", YELLOW))
        return

    os.makedirs(os.path.dirname(new_path), exist_ok=True)
    os.rename(old_path, new_path)
    print(c(f"✔ Renamed template '{old}.html' → '{new}.html'", GREEN))


def rename_in_urls(old: str, new: str):
    strip_bom(URLS_FILE)
    if not os.path.exists(URLS_FILE):
        print(c("⚠ urls.py not found, skipping urls rename.", YELLOW))
        return

    with open(URLS_FILE, "r") as f:
        lines = f.readlines()

    old_url = url_path_from_page(old)
    new_url = url_path_from_page(new)
    old_view = view_name_from_page(old)
    new_view = view_name_from_page(new)

    new_lines = []
    changed_any = False

    for line in lines:
        original = line

        if (
            f"views.{old_view}" in line
            or f"name='{old_view}'" in line
            or f"'{old_url}/'" in line
        ):
            line = line.replace(f"views.{old_view}", f"views.{new_view}")
            line = line.replace(f"name='{old_view}'", f"name='{new_view}'")
            line = line.replace(f"'{old_url}/'", f"'{new_url}/'")
            changed_any = True

        new_lines.append(line)

    if not changed_any:
        print(c(f"⚠ No URL entry found for '{old}' in urls.py.", YELLOW))
    else:
        with open(URLS_FILE, "w") as f:
            f.writelines(new_lines)
        print(c(f"✔ Updated URL route from '{old}' → '{new}' in urls.py", GREEN))


def run_rename_page():
    pages = get_pages()

    if not pages:
        print(c("⚠ No pages available to rename.", YELLOW))
        return

    print(f"\n{c('Pages in', CYAN)} {c(APP_NAME, BOLD)}:\n")
    for i, p in enumerate(pages, start=1):
        print(f" {c(i, CYAN)}. {p}")
    print()

    old_input = input("Enter OLD page name or number: ").strip().lower()
    if not old_input:
        print(c("Old page value cannot be empty.\n", YELLOW))
        return

    if old_input.isdigit():
        idx = int(old_input) - 1
        if 0 <= idx < len(pages):
            old = pages[idx]
        else:
            print(c("⚠ Number out of range.\n", YELLOW))
            return
    else:
        old = old_input

    if old in PROTECTED_PAGES:
        print(c(f"🚫 '{old}' is a protected page and cannot be renamed.\n", RED))
        return

    if old not in pages:
        print(c(f"⚠ Page '{old}' not found.\n", YELLOW))
        return

    new = input("Enter NEW page name: ").strip().lower()

    if not new:
        print(c("New page name cannot be empty.\n", YELLOW))
        return

    if not valid_page_name(new):
        print(
            c(
                "❌ Invalid new page name. Use letters, numbers, underscores; start with a letter.\n",
                RED,
            )
        )
        return

    if old == new:
        print(c("Old and new names are the same, nothing to do.\n", YELLOW))
        return

    print(
        f"\nRenaming page {c(old, CYAN)} → {c(new, CYAN)} in app {c(APP_NAME, BOLD)}...\n"
    )
    rename_in_views(old, new)
    rename_in_template(old, new)
    rename_in_urls(old, new)
    update_navigation()
    print(c("\n✅ Rename process complete.\n", GREEN))


# -----------------------------
#  MAIN MENU LOOP
# -----------------------------
def main():
    while True:
        print(f"\n{c('=== Django App Menu for', CYAN)} {c(APP_NAME, BOLD)} ===")
        print(c("1.", CYAN), "Create page(s)")
        print(c("2.", CYAN), "Delete page(s)")
        print(c("3.", CYAN), "Rename a page")
        print(c("4.", CYAN), "List pages")
        print(c("5.", CYAN), "Update navigation only")
        print(c("6.", CYAN), "Exit")

        choice = input("Choose an option (1–6): ").strip()

        if choice == "1":
            run_createpages()
        elif choice == "2":
            run_deletepages()
        elif choice == "3":
            run_rename_page()
        elif choice == "4":
            list_pages()
        elif choice == "5":
            update_navigation()
        elif choice == "6":
            print("Goodbye 👋")
            break
        else:
            print(c("Invalid choice, try again.\n", YELLOW))


if __name__ == "__main__":
    main()
'@

    $setupBlankContent | Set-Content $setupBlankPath -Encoding utf8
    Write-Host "_setup.blank created." -ForegroundColor Green
    
}
else {
    Write-Host ""
    Write-Host "_setup.blank already exists. Skipping." -ForegroundColor Yellow

}

# -------------------------------------------------
# 0.2 Create $projectName.code-workspace in root if missing
# -------------------------------------------------
$workspaceFile = ".\$projectName.code-workspace"

if (-not (Test-Path $workspaceFile)) {
    Write-Host ""
    Write-Host "Creating $projectName.code-workspace..." -ForegroundColor Yellow

    $workspaceText = @'
{
  "folders": [
    {
      "path": "."
    }
  ],
  "settings": {
    "python.defaultInterpreterPath": "${workspaceFolder}\\.venv\\Scripts\\python.exe",
    "editor.formatOnSave": true,
    "[python]": {
      "editor.defaultFormatter": "ms-python.black-formatter",
      "editor.tabSize": 4,
      "editor.insertSpaces": true
    },
    "python.analysis.typeCheckingMode": "basic",
    "python.analysis.autoImportCompletions": true,
    "python.terminal.activateEnvironment": true,
    "files.exclude": {
      "**/__pycache__": true,
      "**/*.pyc": true
    },
    "files.associations": {
      "**/templates/*.html": "django-html"
    },
    "emmet.includeLanguages": {
      "django-html": "html"
    }
  },
  "extensions": {
    "recommendations": [
      "ms-python.python",
      "ms-python.vscode-pylance",
      "ms-python.black-formatter",
      "batisteo.vscode-django"
    ]
  }
}
'@

    $workspaceText | Set-Content $workspaceFile -Encoding utf8
    Write-Host "$projectName.code-workspace created." -ForegroundColor Green
    $created += "$projectName.code-workspace created."
}
else {
    Write-Host ""
    Write-Host "$projectName.code-workspace already exists. Skipping." -ForegroundColor Yellow
    $skipped += "$projectName.code-workspace already exists."
}

# -------------------------------------------------
# 0.3 Quick "everything already installed" check
# -------------------------------------------------
$venvExists = Test-Path ".\.venv"
$manageExists = Test-Path ".\manage.py"
$websiteExists = Test-Path ".\website"
$vscodeExists = Test-Path ".\.vscode"
$workspaceExists = Test-Path ".\$projectName.code-workspace"

$templatesDirCheck = ".\website\templates\website"
$baseCheck = Join-Path $templatesDirCheck "base.html"
$navCheck = Join-Path $templatesDirCheck "nav.html"
$homeCheck = Join-Path $templatesDirCheck "home.html"
$footerCheck = Join-Path $templatesDirCheck "footer.html"

$templatesOk = (Test-Path $baseCheck) -and (Test-Path $navCheck) -and (Test-Path $homeCheck) -and (Test-Path $footerCheck)

if ($venvExists -and $manageExists -and $websiteExists -and $vscodeExists -and $workspaceExists -and $templatesOk) {
    Write-Host ""
    Write-Host "Detected existing virtual environment, Django project and 'website' app." -ForegroundColor Green
    Write-Host "Everything already set up. Nothing to do. Exiting _project_init.ps1." -ForegroundColor Green
    exit 0
}

# -------------------------------------------------
# 0.4 If .venv does NOT exist: create + install from requirements.txt
# -------------------------------------------------
if (-not $venvExists) {
    Write-Host ""
    Write-Host "No .venv found. Creating virtual environment..." -ForegroundColor Yellow
    py -3 -m venv .venv

    if (!(Test-Path ".\.venv")) {
        Write-Host "ERROR: Virtual environment was not created." -ForegroundColor Red
        $skipped += ".venv (virtual environment not created)"
        exit 1
    }

    Write-Host "Virtual environment created." -ForegroundColor Green
    $created += ".venv (virtual environment created)"

    Write-Host ""
    Write-Host "Activating .venv..." -ForegroundColor Yellow
    & ".\.venv\Scripts\Activate.ps1"
    Write-Host "Virtual environment activated." -ForegroundColor Green
    Write-Host "Python version in venv: " -NoNewline
    python --version
    Write-Host ""

    Write-Host ""
    Write-Host "Upgrading pip and installing packages from requirements.txt..." -ForegroundColor Yellow
    python -m pip install --upgrade pip
    python -m pip install -r $requirementsPath

    Write-Host ""
    Write-Host "Virtual environment setup complete. Continuing with Django project scaffolding..." -ForegroundColor Green
    $created += "Packages from requirements.txt installed in .venv"
}
else {
    Write-Host ""
    Write-Host "Existing .venv found. Will use it." -ForegroundColor Yellow
    $skipped += ".venv (virtual environment already exists)"
}

# -------------------------------------------------
# 1. Activate virtual environment (safe to call again)
# -------------------------------------------------
Write-Host ""
Write-Host "Activating virtual environment (.venv)..." -ForegroundColor Yellow
& ".\.venv\Scripts\Activate.ps1"
$created += ".venv (virtual environment activated)"

Write-Host "Virtual environment activated." -ForegroundColor Green
Write-Host "Python version in venv: " -NoNewline
python --version
Write-Host ""


# -------------------------------------------------
# 3. Create Django project (${projectName}_project)
# -------------------------------------------------
if (Test-Path ".\manage.py") {
    Write-Host ""
    Write-Host "manage.py already exists. Skipping 'startproject'." -ForegroundColor Yellow
    $skipped += "Django project (manage.py already exists)"
}
else {
    Write-Host ""
    Write-Host "Creating Django project: ${projectName}_project ..." -ForegroundColor Yellow
    python -m django startproject ${projectName}_project .

    if (!(Test-Path ".\manage.py")) {
        Write-Host "ERROR: manage.py not found. startproject may have failed." -ForegroundColor Red
        $skipped += "Django project (startproject failed)"
        exit 1
    }

    Write-Host "Project created." -ForegroundColor Green
    $created += "Django project (manage.py created)"
}

# Paths to key files
$settingsPath = ".\${projectName}_project\settings.py"
$urlsPath = ".\${projectName}_project\urls.py"

if (!(Test-Path $settingsPath) -or !(Test-Path $urlsPath)) {
    Write-Host "ERROR: Could not find ${projectName}_project/settings.py or urls.py" -ForegroundColor Red
    $skipped += "Django project (missing settings.py or urls.py)"
    exit 1
}

# -------------------------------------------------
# 4. Create 'website' app
# -------------------------------------------------
if (Test-Path ".\website") {
    Write-Host ""
    Write-Host "App 'website' already exists. Skipping startapp." -ForegroundColor Yellow
    $skipped += "Django app 'website' (already exists)"
}
else {
    Write-Host ""
    Write-Host "Creating Django app: website ..." -ForegroundColor Yellow
    python manage.py startapp website
    Write-Host "App 'website' created." -ForegroundColor Green
    $created += "Django app 'website' (created)"
}

# -------------------------------------------------
# 5. Ensure 'website' is in INSTALLED_APPS
# -------------------------------------------------
Write-Host ""
Write-Host "Adding 'website' to INSTALLED_APPS (if missing)..." -ForegroundColor Yellow

$settingsLines = Get-Content $settingsPath

if ($settingsLines -notcontains '    "website",' -and $settingsLines -notcontains "    'website',") {

    $insertIndex = -1

    for ($i = 0; $i -lt $settingsLines.Length; $i++) {
        if ($settingsLines[$i] -match "django\.contrib\.staticfiles") {
            $insertIndex = $i + 1
            break
        }
    }

    if ($insertIndex -gt -1) {
        $before = $settingsLines[0..($insertIndex - 1)]
        $after = $settingsLines[$insertIndex..($settingsLines.Length - 1)]
        $newLine = '    "website",'
        $settingsLines = $before + $newLine + $after
        $settingsLines | Set-Content $settingsPath -Encoding utf8
        Write-Host "'website' added to INSTALLED_APPS." -ForegroundColor Green
        $created += "'website' added to INSTALLED_APPS"
    }
    else {
        Write-Host "WARNING: Could not automatically insert 'website' into INSTALLED_APPS. Please add it manually." -ForegroundColor Yellow
        $skipped += "'website' not added to INSTALLED_APPS (insertion point not found)"
    }
}
else {
    Write-Host "'website' already present in INSTALLED_APPS." -ForegroundColor Yellow
    $skipped += "'website' already present in INSTALLED_APPS"
}

# -------------------------------------------------
# 6. Ensure APP_DIRS = True in TEMPLATES
# -------------------------------------------------
Write-Host ""
Write-Host "Ensuring APP_DIRS = True in TEMPLATES setting..." -ForegroundColor Yellow

$settingsText = Get-Content $settingsPath -Raw

if ($settingsText -notmatch "APP_DIRS\s*=\s*True") {
    $settingsText = $settingsText -replace "APP_DIRS\s*=\s*False", "APP_DIRS = True"
    if ($settingsText -notmatch "APP_DIRS\s*=\s*True") {
        $settingsText = $settingsText -replace "'DIRS': \[\],", "'DIRS': [],`r`n        'APP_DIRS': True,"
    }
    $settingsText | Set-Content $settingsPath -Encoding utf8
    Write-Host "APP_DIRS set to True." -ForegroundColor Green
    $created += "APP_DIRS set to True"
}
else {
    Write-Host "APP_DIRS already set to True." -ForegroundColor Yellow
    $skipped += "APP_DIRS already set to True"
}

# -------------------------------------------------
# 7. Ensure website/views.py exists AND has a home() view
# -------------------------------------------------
Write-Host ""
Write-Host "Ensuring website/views.py and home() view exist..." -ForegroundColor Yellow

$viewsFilePath = ".\website\views.py"

if (-not (Test-Path $viewsFilePath)) {
    # File doesn't exist at all → create it with import + home()
    $viewsPy = @'
from django.shortcuts import render


def home(request):
    return render(request, "website/home.html")
'@

    $viewsPy | Set-Content $viewsFilePath -Encoding utf8
    Write-Host "website/views.py created with home() view." -ForegroundColor Green
    $created += "website/views.py (created with home())"
}
else {
    # File exists (from startapp or custom code) → only add home() if missing
    $viewsContent = Get-Content $viewsFilePath -Raw

    # Make sure we have the render import
    if ($viewsContent -notmatch "from\s+django\.shortcuts\s+import\s+render") {
        Write-Host "Adding 'from django.shortcuts import render' to existing views.py..." -ForegroundColor Yellow
        $created += "Added 'from django.shortcuts import render' to website/views.py"

        $viewsContent = "from django.shortcuts import render`r`n`r`n" + $viewsContent
        $viewsContent | Set-Content $viewsFilePath -Encoding utf8
    }

    # Reload content after possible import insert
    $viewsContent = Get-Content $viewsFilePath -Raw

    if ($viewsContent -notmatch "def\s+home\s*\(") {
        Write-Host "Appending home() view to existing views.py..." -ForegroundColor Yellow
        $created += "Appended home() view to website/views.py"

        $homeFunc = @'

def home(request):
    return render(request, "website/home.html")
'@

        $homeFunc | Add-Content $viewsFilePath -Encoding utf8
        Write-Host "home() view added to website/views.py." -ForegroundColor Green
        $created += "website/views.py (home() added)"
    }
    else {
        Write-Host "website/views.py already has a home() view. Not modifying it." -ForegroundColor Yellow
        $skipped += "website/views.py (home() already present)"
    }
}



# -------------------------------------------------
# 8. Create website/urls.py (ONLY if missing)
# -------------------------------------------------
Write-Host ""
Write-Host "Ensuring website/urls.py exists..." -ForegroundColor Yellow

$urlsFilePath = ".\website\urls.py"

if (-not (Test-Path $urlsFilePath)) {
    $urlsPy = @'
from django.urls import path
from .views import home

urlpatterns = [
    path("", home, name="home"),
]
'@

    $urlsPy | Set-Content $urlsFilePath -Encoding utf8
    Write-Host "website/urls.py created." -ForegroundColor Green
    $created += "website/urls.py (created)"
}
else {
    Write-Host "website/urls.py already exists. Not overwriting." -ForegroundColor Yellow
    $skipped += "website/urls.py (already exists)"
}


# -------------------------------------------------
# 9. Create templates for website: base, nav, home, footer
# -------------------------------------------------
Write-Host ""
Write-Host "Creating templates for 'website' (base.html, nav.html, home.html, footer.html)..." -ForegroundColor Yellow

$templatesDir = ".\website\templates\website"
if (-not (Test-Path $templatesDir)) {
    New-Item -ItemType Directory -Path $templatesDir | Out-Null
}

$basePath = Join-Path $templatesDir "base.html"
$navPath = Join-Path $templatesDir "nav.html"
$homePath = Join-Path $templatesDir "home.html"
$footerPath = Join-Path $templatesDir "footer.html"

if (-not (Test-Path $navPath)) {
    $navHtml = @'
{% load static %}
<nav class="navbar navbar-expand-lg navbar-dark bg-dark mb-4">
  <div class="container-fluid">
    <a class="navbar-brand" href="/">
      <img src="{% static 'images/logo.png' %}" style="height: 40px; margin-top: -5px" />
      {{PROJECT_NAME}}
    </a>
    <button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="#mainNav">
      <span class="navbar-toggler-icon"></span>
    </button>
    <div class="collapse navbar-collapse" id="mainNav">
      <ul class="navbar-nav ms-auto mb-2 mb-lg-0">
        <!-- AUTO-GENERATED NAV START -->
        <!-- AUTO-GENERATED NAV END -->
      </ul>
    </div>
  </div>
</nav>
'@
    $navHtml = $navHtml.Replace("{{PROJECT_NAME}}", $projectName)
    $navHtml | Set-Content $navPath -Encoding utf8
    Write-Host "Created website/nav.html" -ForegroundColor Green
    $created += "website/nav.html (created)"
}
else {
    Write-Host "website/nav.html already exists, skipping." -ForegroundColor Yellow
    $skipped += "website/nav.html (already exists)"
}

if (-not (Test-Path $footerPath)) {
    $footerHtml = @'
<footer class="bg-dark text-white text-center py-3 mt-5">
  <div class="container">
    <small>&copy; 2025 Your Project Name. All rights reserved.</small>
  </div>
</footer>
'@
    $footerHtml | Set-Content $footerPath -Encoding utf8
    Write-Host "Created website/footer.html" -ForegroundColor Green
    $created += "website/footer.html (created)"
}
else {
    Write-Host "website/footer.html already exists, skipping." -ForegroundColor Yellow
    $skipped += "website/footer.html (already exists)"
}

if (-not (Test-Path $basePath)) {
    $baseHtml = @'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{% block title %}Website{% endblock %}</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
</head>
<body class="bg-light">
    {% include "website/nav.html" %}
    <div class="container my-4">
        {% block content %}{% endblock %}
    </div>
    {% include "website/footer.html" %}
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
'@
    $baseHtml | Set-Content $basePath -Encoding utf8
    Write-Host "Created website/base.html" -ForegroundColor Green
    $created += "website/base.html (created)"
}
else {
    Write-Host "website/base.html already exists, skipping." -ForegroundColor Yellow
    $skipped += "website/base.html (already exists)"
}

if (-not (Test-Path $homePath)) {
    $homeHtml = @'
{% extends "website/base.html" %}

{% block title %}Home | Website{% endblock %}

{% block content %}
<div class="text-center my-5">
    <h1>Website for the {{PROJECT_NAME}} successfully running</h1>
    <p>This home page was generated by _project_init.ps1.</p>
</div>
{% endblock %}
'@
    $homeHtml = $homeHtml.Replace("{{PROJECT_NAME}}", $folderName)
    $homeHtml | Set-Content $homePath -Encoding utf8
    Write-Host "Created website/home.html" -ForegroundColor Green
    $created += "website/home.html (created)"
}
else {
    Write-Host "website/home.html already exists, skipping." -ForegroundColor Yellow
    $skipped += "website/home.html (already exists)"
}

# -------------------------------------------------
# 10. Download default logo into website/static/images/logo.png
# -------------------------------------------------
Write-Host ""
Write-Host "Ensuring default logo.png exists in website/static/images/..." -ForegroundColor Yellow

$staticImagesDir = ".\website\static\images"
$logoPath = Join-Path $staticImagesDir "logo.png"
$logoUrl = "https://raw.githubusercontent.com/naspenang/pub-static/refs/heads/main/nologo.png"

if (-not (Test-Path $staticImagesDir)) {
    New-Item -ItemType Directory -Path $staticImagesDir -Force | Out-Null
}

if (-not (Test-Path $logoPath)) {
    try {
        Write-Host "Downloading default logo from $logoUrl ..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $logoUrl -OutFile $logoPath -UseBasicParsing
        Write-Host "Default logo saved to $logoPath" -ForegroundColor Green
        $created += "website/static/images/logo.png (downloaded)"
    }
    catch {
        Write-Host "WARNING: Failed to download default logo: $($_.Exception.Message)" -ForegroundColor Red
        $skipped += "website/static/images/logo.png (download failed)"
    }
}
else {
    Write-Host "logo.png already exists in website/static/images, not overwriting." -ForegroundColor Yellow
    $skipped += "website/static/images/logo.png (already exists)"
}


# -------------------------------------------------
# 11. VS Code .vscode/launch.json and tasks.json
# -------------------------------------------------
Write-Host ""
Write-Host "Ensuring VS Code .vscode/ files exist..." -ForegroundColor Yellow

$vscodeDir = ".\.vscode"
if (-not (Test-Path $vscodeDir)) {
    New-Item -ItemType Directory -Path $vscodeDir | Out-Null
}

$settingsModule = "${projectName}_project.settings"
$projectRoot = Get-Location
$venvPython = Join-Path $projectRoot ".venv\Scripts\python.exe"

if (-not (Test-Path $venvPython)) {
    Write-Host "WARNING: .venv\\Scripts\\python.exe not found. Using 'python' fallback in tasks.json." -ForegroundColor Yellow
    $skipped += ".venv\\Scripts\\python.exe not found, using 'python' fallback"
    $venvPython = "python"
}
else {
    Write-Host "Using venv python at: $venvPython" -ForegroundColor Green
    $created += "Using venv python at: $venvPython"
}

# ---------- launch.json (ONLY if missing) ----------
$launchFile = Join-Path $vscodeDir "launch.json"

if (-not (Test-Path $launchFile)) {
    $launchJson = @'
{
    "version": "0.2.0",
    "configurations": [
        {
            "type": "python",
            "request": "launch",
            "program": "${workspaceFolder}/manage.py",
            "console": "integratedTerminal",
            "django": true,
            "env": {
                "DJANGO_SETTINGS_MODULE": "__SETTINGS_MODULE__"
            },
            "python": "${workspaceFolder}/.venv/Scripts/python.exe",
            "name": "Django: Runserver (Debug)",
            "args": [
                "runserver",
                "8000"
            ],
            "justMyCode": false,
            "serverReadyAction": {
                "action": "openExternally",
                "pattern": "Starting development server at (http://127\\.0\\.0\\.1:8000/?)",
                "uriFormat": "%s"
            }
        },
        {
            "type": "python",
            "request": "launch",
            "program": "${workspaceFolder}/manage.py",
            "console": "integratedTerminal",
            "django": true,
            "env": {
                "DJANGO_SETTINGS_MODULE": "__SETTINGS_MODULE__"
            },
            "python": "${workspaceFolder}/.venv/Scripts/python.exe",
            "name": "Django: Runserver (No Debug)",
            "args": [
                "runserver",
                "8000",
                "--noreload"
            ],
            "justMyCode": true,
            "serverReadyAction": {
                "action": "openExternally",
                "pattern": "Starting development server at (http://127\\.0\\.0\\.1:8000/?)",
                "uriFormat": "%s"
            }
        },
        {
            "type": "python",
            "request": "launch",
            "program": "${workspaceFolder}/manage.py",
            "console": "integratedTerminal",
            "django": true,
            "env": {
                "DJANGO_SETTINGS_MODULE": "__SETTINGS_MODULE__"
            },
            "python": "${workspaceFolder}/.venv/Scripts/python.exe",
            "name": "Django: Tests",
            "args": [
                "test"
            ],
            "justMyCode": true
        },
        {
            "type": "python",
            "request": "launch",
            "program": "${workspaceFolder}/manage.py",
            "console": "integratedTerminal",
            "django": true,
            "env": {
                "DJANGO_SETTINGS_MODULE": "__SETTINGS_MODULE__"
            },
            "python": "${workspaceFolder}/.venv/Scripts/python.exe",
            "name": "Django: Shell",
            "args": [
                "shell"
            ],
            "justMyCode": true
        }
    ]
}
'@

    $launchJson = $launchJson.Replace("__SETTINGS_MODULE__", $settingsModule)
    $launchJson | Set-Content $launchFile -Encoding utf8
    Write-Host "VS Code launch.json created at $launchFile" -ForegroundColor Green
    Write-Host "DJANGO_SETTINGS_MODULE = $settingsModule" -ForegroundColor Cyan
    $created += "VS Code launch.json created"
}
else {
    Write-Host "launch.json already exists. Not overwriting." -ForegroundColor Yellow
    $skipped += "VS Code launch.json (already exists)"
}

# ---------- tasks.json (ONLY if missing) ----------
$tasksFile = Join-Path $vscodeDir "tasks.json"

if (-not (Test-Path $tasksFile)) {
    $tasksJson = @'
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "Django: Runserver",
            "type": "shell",
            "command": "__VENV_PYTHON__",
            "args": ["manage.py", "runserver"],
            "group": {
                "kind": "build",
                "isDefault": true
            },
            "problemMatcher": []
        },
        {
            "label": "Django: Make Migrations",
            "type": "shell",
            "command": "__VENV_PYTHON__",
            "args": ["manage.py", "makemigrations"],
            "group": "none",
            "problemMatcher": []
        },
        {
            "label": "Django: Run Migrations",
            "type": "shell",
            "command": "__VENV_PYTHON__",
            "args": ["manage.py", "migrate"],
            "group": "none",
            "problemMatcher": []
        }
    ]
}
'@

    $tasksJson = $tasksJson.Replace("__VENV_PYTHON__", $venvPython)
    $tasksJson | Set-Content $tasksFile -Encoding utf8
    Write-Host "VS Code tasks.json created at $tasksFile" -ForegroundColor Green
    $created += "VS Code tasks.json created"
}
else {
    Write-Host "tasks.json already exists. Not overwriting." -ForegroundColor Yellow
    $skipped += "VS Code tasks.json (already exists)"
}

# ---------- settings.json (ONLY if missing) ----------
$settingsFileVs = Join-Path $vscodeDir "settings.json"

if (-not (Test-Path $settingsFileVs)) {
    $settingsData = @{
        "python.terminal.activateEnvironment" = $true
        "python.defaultInterpreterPath"       = ".venv\\Scripts\\python.exe"
    }
    $settingsJsonVs = $settingsData | ConvertTo-Json -Depth 5
    $settingsJsonVs | Set-Content $settingsFileVs -Encoding utf8
    Write-Host "✅ VS Code settings.json written for auto-venv." -ForegroundColor Green
    $created += "VS Code settings.json created"
}
else {
    Write-Host "settings.json already exists. Not overwriting." -ForegroundColor Yellow
    $skipped += "VS Code settings.json (already exists)"
}


# -------------------------------------------------
# 12. Update project urls.py to point root URL ('/') to website app
# -------------------------------------------------
Write-Host ""
Write-Host "Updating project urls.py to point root URL ('/') to website app..." -ForegroundColor Yellow

$urlsLines = Get-Content $urlsPath

for ($i = 0; $i -lt $urlsLines.Length; $i++) {
    if ($urlsLines[$i] -match "from django\.urls import path" -and $urlsLines[$i] -notmatch "include") {
        $urlsLines[$i] = "from django.urls import path, include"
        break
    }
}

$hasWebsiteRoute = $false
foreach ($line in $urlsLines) {
    if ($line -match "website\.urls") {
        $hasWebsiteRoute = $true
        break
    }
}

if (-not $hasWebsiteRoute) {
    $insertIndex = -1
    for ($i = 0; $i -lt $urlsLines.Length; $i++) {
        if ($urlsLines[$i] -match "admin\.site\.urls") {
            $insertIndex = $i + 1
            break
        }
    }

    if ($insertIndex -gt -1) {
        $before = $urlsLines[0..($insertIndex - 1)]
        $after = $urlsLines[$insertIndex..($urlsLines.Length - 1)]
        $newLine = '    path("", include("website.urls")),'
        
        $urlsLines = $before + $newLine + $after
        $urlsLines | Set-Content $urlsPath -Encoding utf8
        Write-Host 'Root URL now points to website app.' -ForegroundColor Green
        $created += 'Root URL points to website app'
    }
    else {
        Write-Host "WARNING: Could not automatically insert website route in urls.py. Please add it manually." -ForegroundColor Yellow
        $skipped += "website route not added to urls.py (insertion point not found)"
    }
}
else {
    Write-Host "website route already exists in urls.py." -ForegroundColor Yellow
    $skipped += "website route already exists in urls.py"
}

# -------------------------------------------------
# 13. Copy _setup.blank to every app folder as _setup.py (if present)
# -------------------------------------------------
$sourceFile = "_setup.blank"

if (-not (Test-Path $sourceFile)) {
    Write-Host "Source file '_setup.blank' not found, skipping _setup.py copies." -ForegroundColor Yellow
    $skipped += "_setup.py copies skipped (_setup.blank not found)"
}
else {
    $targets = Get-ChildItem -Recurse -Filter "apps.py"

    foreach ($t in $targets) {
        $targetFolder = $t.Directory.FullName
        $destPath = Join-Path $targetFolder "_setup.py"

        Copy-Item -Path $sourceFile -Destination $destPath -Force
        Write-Host "Copied _setup.py to: $destPath"
        $created += "_setup.py copied to $destPath"
    }
}

# -------------------------------------------------
# 12.5 Re-activate venv and run collectstatic (safe mode)
# -------------------------------------------------
Write-Host ""

if (Test-Path ".\.venv\Scripts\Activate.ps1" -and (Test-Path ".\manage.py")) {
    Write-Host "Re-activating virtual environment (.venv) before collectstatic..." -ForegroundColor Yellow
    & ".\.venv\Scripts\Activate.ps1"
    Write-Host "Virtual environment re-activated." -ForegroundColor Green

    Write-Host "Running 'python manage.py collectstatic --noinput'..." -ForegroundColor Yellow
    try {
        python manage.py collectstatic --noinput
        Write-Host "Static files collected successfully." -ForegroundColor Green
        $created += "Static files collected (collectstatic)"
    }
    catch {
        Write-Host "WARNING: collectstatic failed: $($_.Exception.Message)" -ForegroundColor Red
        $skipped += "collectstatic (failed)"
    }
}
else {
    Write-Host "Skipping collectstatic: .venv or manage.py not found." -ForegroundColor Yellow
    $skipped += "collectstatic (skipped: missing .venv or manage.py)"
}



# -------------------------------------------------
# 14. Summary of created/skipped files
# -------------------------------------------------
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan

Write-Host "  Created:" -ForegroundColor Green
if ($created.Count -eq 0) {
    Write-Host "   - (nothing new created)" -ForegroundColor DarkGreen
}
else {
    $created | ForEach-Object { Write-Host "   - $_" -ForegroundColor Green }
}

Write-Host "  Skipped (already existed):" -ForegroundColor Yellow
if ($skipped.Count -eq 0) {
    Write-Host "   - (nothing was skipped)" -ForegroundColor DarkYellow
}
else {
    $skipped | ForEach-Object { Write-Host "   - $_" -ForegroundColor Yellow }
}



# -------------------------------------------------
# Done
# -------------------------------------------------
Write-Host ""
Write-Host "=== $projectName Django base setup + Website app completed ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Now you can run:" -ForegroundColor Cyan
Write-Host "    python manage.py runserver" -ForegroundColor Cyan
Write-Host ""
Write-Host "Then open http://127.0.0.1:8000/ and you should see:" -ForegroundColor Cyan
Write-Host "    Website for the $projectName successfully running" -ForegroundColor Green
Write-Host ""
Write-Host "Happy coding! 🚀" -ForegroundColor Cyan

