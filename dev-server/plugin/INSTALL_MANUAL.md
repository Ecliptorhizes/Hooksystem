# Manual Plugin Install (recommended)

**Roblox Studio does not load .rbxm/.rbxmx files placed directly in the Plugins folder.** You must create the plugin from within Studio using "Save as Local Plugin".

## Steps

1. **Open Roblox Studio** and your Hooksystem place.

2. **Create a new Script:**
   - In Explorer, right-click **ServerStorage** → Insert Object → **Script**
   - Rename it to `DevTuningBridge`

3. **Copy the plugin code:**
   - Open `dev-server/plugin/DevTuningBridge.plugin.lua` in a text editor
   - Copy the **entire** contents (including the toolbar lines at the top)

4. **Paste into the Script** – replace the default `print("Hello world!")` completely.

5. **Save as Local Plugin:**
   - Select the Script in Explorer (single-click it)
   - Go to **Plugins** menu (top bar) → **Save as Local Plugin**
   - In the dialog, click **Save**

6. **Restart Studio** completely (quit and reopen).

7. **Verify:** You should see a "Hooksystem" section in the Plugins tab with a "Dev Tuning" button.

8. **Enable HTTP requests:** Game Settings → Security → Allow HTTP Requests.

## Mac Plugins folder

`~/Library/Application Support/Roblox/Plugins`

Finder → Go → Go to Folder (⌘⇧G) → paste that path.
