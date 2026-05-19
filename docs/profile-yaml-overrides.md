# Profile YAML overrides

This fork adds a file-based profile override layer for Clash Meta for Android.

## Scope

The feature is intentionally YAML-only. It does not execute JavaScript override scripts.
It is designed to preserve the normal CMFA subscription refresh path while reapplying
local overrides after every profile fetch.

## Directories

For each profile, overrides are read from:

```text
<profile-dir>/overrides/*.yaml
<profile-dir>/overrides/*.yml
```

Global overrides are read first from the app-private directory:

```text
<app files>/global-overrides/*.yaml
<app files>/global-overrides/*.yml
```

Profile overrides are read after global overrides. Within each directory, files are
applied in lexicographic filename order. Prefix files with numbers such as
`00-base.yaml` and `90-ai.yaml` to control order.

## Managing profile overrides in the app

The profile file browser exposes an `overrides` directory next to `config.yaml`
and `providers`. Put profile-specific YAML patch files there. URL profiles can
still edit this directory even though their downloaded `config.yaml` is read-only.

Existing profiles created before this feature may receive the directory the next
time they are opened in the file browser or refreshed.

After every successful subscription download, CMFA applies global overrides first,
then profile overrides, validates the merged Mihomo config, and only then commits
the refreshed profile. If validation fails, the previous generated config is
restored and the profile update fails instead of saving a broken config.

## Merge semantics

The merge behavior follows Mihomo Party's YAML override convention for common cases:

```yaml
+rules:
  - DOMAIN-SUFFIX,example.com,DIRECT

proxy-groups+:
  - name: AI
    type: select
    proxies:
      - DIRECT

mixed-port!: 7890
```

- `+key`: prepend array items to `key`.
- `key+`: append array items to `key`.
- `key!`: force replace `key`.
- plain object keys: recursively merge.
- plain array/scalar keys: replace.

## Update lifecycle

On profile import and on every scheduled URL refresh, CMFA now does this:

```text
fetch upstream config.yaml
apply global overrides
apply profile overrides
validate through the existing fetch/load validation path
commit processing directory to imported profile directory
```

If fetch, merge, or validation fails, the old imported profile remains untouched.
