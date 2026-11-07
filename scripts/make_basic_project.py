"""Rewrites project.yml in place for the BASIC TestFlight build:
no widget extension, no App Group, no Time Sensitive entitlement.
Those need extra Apple Developer portal setup; the app itself runs fine without them
(the widget just isn't installed). Used by the TestFlight workflow."""
import yaml

with open("project.yml") as f:
    spec = yaml.safe_load(f)

app = spec["targets"]["InboxButler"]
app["dependencies"] = [d for d in app.get("dependencies", []) if d.get("target") != "InboxButlerWidget"]
spec["targets"].pop("InboxButlerWidget", None)

props = app.get("entitlements", {}).get("properties", {})
props.pop("com.apple.security.application-groups", None)
props.pop("com.apple.developer.usernotifications.time-sensitive", None)
if not props:
    app.pop("entitlements", None)

with open("project.yml", "w") as f:
    yaml.safe_dump(spec, f, sort_keys=False)
print("project.yml rewritten for the basic build (no widget, no App Group).")
