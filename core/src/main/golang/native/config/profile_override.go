package config

import (
	"fmt"
	"os"
	P "path"
	"sort"
	"strings"

	yaml "gopkg.in/yaml.v3"
)

const profileOverrideDirName = "overrides"

// ApplyProfileOverrides applies Mihomo Party style YAML override files to profilePath/config.yaml.
// It is intentionally file based: globalOverrideDir/*.yaml are applied first, then
// profilePath/overrides/*.yaml are applied. Files are sorted by filename so users can
// control order with prefixes such as 00-base.yaml and 90-ai.yaml.
//
// The write is transactional at the profile directory level: if merged config validation
// fails, config.yaml is restored to its previous content and the caller receives an error.
func ApplyProfileOverrides(profilePath string, globalOverrideDir string) error {
	configPath := P.Join(profilePath, "config.yaml")

	originalData, err := os.ReadFile(configPath)
	if err != nil {
		return fmt.Errorf("read base config: %w", err)
	}

	base, err := parseYamlMap(originalData, configPath)
	if err != nil {
		return fmt.Errorf("parse base config: %w", err)
	}

	overrideFiles := make([]string, 0)
	overrideFiles = append(overrideFiles, listOverrideFiles(globalOverrideDir)...)
	overrideFiles = append(overrideFiles, listOverrideFiles(P.Join(profilePath, profileOverrideDirName))...)

	if len(overrideFiles) == 0 {
		return nil
	}

	for _, file := range overrideFiles {
		patch, err := readYamlMap(file)
		if err != nil {
			return fmt.Errorf("read override %s: %w", file, err)
		}
		deepMerge(base, patch, true)
	}

	merged, err := yaml.Marshal(base)
	if err != nil {
		return fmt.Errorf("marshal merged config: %w", err)
	}

	if err := os.WriteFile(configPath, merged, 0600); err != nil {
		return fmt.Errorf("write merged config: %w", err)
	}

	if err := validateProfileConfig(profilePath); err != nil {
		restoreErr := os.WriteFile(configPath, originalData, 0600)
		if restoreErr != nil {
			return fmt.Errorf("validate merged config: %w; restore original config: %v", err, restoreErr)
		}
		return fmt.Errorf("validate merged config: %w", err)
	}

	return nil
}

func readYamlMap(file string) (map[string]any, error) {
	data, err := os.ReadFile(file)
	if err != nil {
		return nil, err
	}

	return parseYamlMap(data, file)
}

func parseYamlMap(data []byte, label string) (map[string]any, error) {
	if len(strings.TrimSpace(string(data))) == 0 {
		return map[string]any{}, nil
	}

	out := map[string]any{}
	if err := yaml.Unmarshal(data, &out); err != nil {
		return nil, fmt.Errorf("%s: %w", label, err)
	}

	if out == nil {
		out = map[string]any{}
	}

	return out, nil
}

func validateProfileConfig(profilePath string) error {
	rawCfg, err := UnmarshalAndPatch(profilePath)
	if err != nil {
		return err
	}

	cfg, err := Parse(rawCfg)
	if err != nil {
		return err
	}

	destroyProviders(cfg)
	return nil
}

func listOverrideFiles(dir string) []string {
	if dir == "" {
		return nil
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}

	files := make([]string, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		name := entry.Name()
		lower := strings.ToLower(name)
		if strings.HasSuffix(lower, ".yaml") || strings.HasSuffix(lower, ".yml") {
			files = append(files, P.Join(dir, name))
		}
	}

	sort.Strings(files)
	return files
}

func isObject(value any) bool {
	switch value.(type) {
	case map[string]any, map[any]any:
		return true
	default:
		return false
	}
}

func toStringMap(value any) map[string]any {
	switch v := value.(type) {
	case map[string]any:
		return v
	case map[any]any:
		out := make(map[string]any, len(v))
		for key, val := range v {
			out[fmt.Sprint(key)] = val
		}
		return out
	default:
		return nil
	}
}

func toSlice(value any) []any {
	switch v := value.(type) {
	case []any:
		return v
	case []map[string]any:
		out := make([]any, len(v))
		for i := range v {
			out[i] = v[i]
		}
		return out
	case []string:
		out := make([]any, len(v))
		for i := range v {
			out[i] = v[i]
		}
		return out
	default:
		return nil
	}
}

func trimWrap(key string) string {
	if strings.HasPrefix(key, "<") && strings.HasSuffix(key, ">") && len(key) >= 2 {
		return key[1 : len(key)-1]
	}
	return key
}

func deepMerge(target map[string]any, other map[string]any, isOverride bool) map[string]any {
	for key, value := range other {
		if strings.HasSuffix(key, "!") {
			k := trimWrap(strings.TrimSuffix(key, "!"))
			if objectValue := toStringMap(value); objectValue != nil {
				target[k] = objectValue
			} else if arrayValue := toSlice(value); arrayValue != nil {
				target[k] = arrayValue
			} else {
				target[k] = value
			}
			continue
		}

		if isObject(value) {
			k := trimWrap(key)
			existing := toStringMap(target[k])
			if existing == nil {
				existing = map[string]any{}
				target[k] = existing
			}
			deepMerge(existing, toStringMap(value), isOverride)
			continue
		}

		if arrayValue := toSlice(value); arrayValue != nil {
			if isOverride && strings.HasPrefix(key, "+") {
				k := trimWrap(strings.TrimPrefix(key, "+"))
				target[k] = append(append([]any{}, arrayValue...), toSliceOrEmpty(target[k])...)
				continue
			}
			if isOverride && strings.HasSuffix(key, "+") {
				k := trimWrap(strings.TrimSuffix(key, "+"))
				target[k] = append(toSliceOrEmpty(target[k]), arrayValue...)
				continue
			}

			k := trimWrap(key)
			target[k] = arrayValue
			continue
		}

		target[key] = value
	}

	return target
}

func toSliceOrEmpty(value any) []any {
	if arrayValue := toSlice(value); arrayValue != nil {
		return append([]any{}, arrayValue...)
	}
	return []any{}
}
