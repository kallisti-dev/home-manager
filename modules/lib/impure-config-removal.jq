# Removes from a configuration file the settings that Home Manager last
# applied to it and that are no longer declared, for
# lib.hm.generators.mkImpureConfigMerger.
#
# Input: the file's contents. Output: the contents without those settings.
# $previous: the settings last applied, as recorded.
# $static: the settings declared now.
# $rules: the merger's `removal` rules with their defaults filled in,
#   {keep, atomic, sets: [{path, keep}], maps: [{path, keys, atomic}]}.
#   Paths are arrays of keys in which "*" matches any key and [] is the
#   whole file.
#
# The recorded settings are walked. hm_rule chooses the rule for each
# recorded value, and the function for that rule removes the value from the
# file. Removal functions take the current value as input and output the new
# value, or nothing when the value goes.

# Whether the path $p matches one of $patterns.
def hm_matches($patterns):
  . as $p
  | any($patterns[];
      length == ($p | length)
      and (. as $pattern | all(range(0; $p | length); $pattern[.] == "*" or $pattern[.] == $p[.])));

# Whether the path $p exists in the input. A null value counts.
def hm_has_path($p):
  if $p == [] then
    true
  elif type == "object" and has($p[0]) then
    .[$p[0]] | hm_has_path($p[1:])
  else
    false
  end;

# Whether the path $p is declared in the input, the static settings. The
# whole file is declared while any setting is.
def hm_declared($p):
  if $p == [] then length > 0 else hm_has_path($p) end;

# The array declared at $p in the input, or [] when there is none.
def hm_declared_array($p):
  if hm_has_path($p) then getpath($p) | if type == "array" then . else [] end else [] end;

# Whether the input still holds every value of $recorded that it has not
# deleted. A key that is gone does not count as a change, since applications
# drop settings they normalize; a value of another type does, since the
# object was replaced rather than edited.
def hm_unchanged($recorded):
  if ($recorded | type) == "object" and ($recorded | length) > 0 then
    . as $current
    | type == "object"
      and all($recorded | keys[]; . as $key
          | ($current | has($key) | not) or ($current[$key] | hm_unchanged($recorded[$key])))
  else
    . == $recorded
  end;

# The first of $rules whose path matches $p, or null.
def hm_rule_at($p; $rules):
  first(($rules[] | select(.path as $pattern | $p | hm_matches([$pattern]))), null);

# The rule for the recorded value $recorded at $p, given the static settings
# as input. In order of precedence:
#   keep: the value stays, with everything under it;
#   set, map: a recorded array that the application extends, by the matching
#     rule of $rules.sets or $rules.maps;
#   atomic: a value that is no longer declared goes or stays whole;
#   object: each key of a recorded object goes by its own rule;
#   declared: a value that is still declared stays;
#   leaf: the value goes while it still equals the recorded value.
def hm_rule($p; $recorded; $rules):
  hm_rule_at($p; $rules.sets) as $set
  | hm_rule_at($p; $rules.maps) as $map
  | if $p | hm_matches($rules.keep) then
      {kind: "keep"}
    elif ($recorded | type) == "array" and $set != null then
      {kind: "set", rule: $set}
    elif ($recorded | type) == "array" and $map != null then
      {kind: "map", rule: $map}
    elif ($p | hm_matches($rules.atomic)) and (hm_declared($p) | not) then
      {kind: "atomic"}
    elif ($recorded | type) == "object" and ($recorded | length) > 0 then
      {kind: "object"}
    elif hm_declared($p) then
      {kind: "declared"}
    else
      {kind: "leaf"}
    end;

def hm_remove_leaf($recorded):
  if . == $recorded then empty else . end;

# An atomic value goes with the keys the application added to it, unless a
# recorded value in it has changed.
def hm_remove_atomic($recorded):
  if hm_unchanged($recorded) then empty else . end;

# An array goes once the removal emptied it or it is still the empty array
# that was recorded, unless it is declared. One the application emptied
# stays.
def hm_remove_emptied($p; $recorded; $static; $current):
  if . == [] and ($current != [] or $recorded == []) and ($static | hm_declared($p) | not) then
    empty
  else
    .
  end;

# From a set, the recorded elements that are neither declared nor protected
# by $rule.keep go, and elements the application added stay. Protected
# elements go with the last other element.
def hm_remove_set($p; $recorded; $static; $rule):
  . as $current
  | ($static | hm_declared_array($p)) as $declared
  | $current - ($recorded - $declared - $rule.keep)
  | if (. - $rule.keep) == [] then [] else . end
  | hm_remove_emptied($p; $recorded; $static; $current);

# The key of an element of a keyed array.
def hm_key($keys):
  if type == "object" then [.[$keys[]]] else [.] end;

def hm_merge_all:
  reduce (.[] | objects) as $value ({}; . * $value);

# Removes from the input, the value at $p, the recorded settings $recorded
# that are no longer declared, by the rule chosen for each. Outputs the new
# value, or nothing when the value goes.
def hm_remove($p; $recorded; $static; $rules):
  # Each key of the object goes by its own rule, and the others keep their
  # order. The object goes once the removal emptied it, unless it is
  # declared. One replaced by a value of another type has nothing left to
  # remove.
  def fields:
    if type != "object" then
      .
    else
      . as $current
      | with_entries(
          .key as $key
          | if $recorded | has($key) then
              [.value | hm_remove($p + [$key]; $recorded[$key]; $static; $rules)] as $value
              | if $value == [] then empty else .value = $value[0] end
            else
              .
            end)
      | if . == {} and $current != {} and ($static | hm_declared($p) | not) then empty else . end
    end;
  # An element of a keyed array is matched to the recorded and declared
  # elements by its key fields. One without a recorded counterpart, or that
  # is not an object, stays. With `atomic`, an element that is no longer
  # declared goes or stays whole. Otherwise the element is treated as a file
  # of its own whose key fields are kept, and goes once only they are left
  # and it is no longer declared.
  def element($declared; $rule):
    hm_key($rule.keys) as $key
    | [$recorded[] | select(hm_key($rule.keys) == $key)] as $recordedElement
    | if $recordedElement == [] or type != "object" then
        .
      else
        ($recordedElement | hm_merge_all) as $previous
        | ([$declared[] | select(hm_key($rule.keys) == $key)] | hm_merge_all) as $static
        | if $static == {} and $rule.atomic then
            hm_remove_atomic($previous)
          else
            hm_remove([]; $previous; $static; {keep: [$rule.keys[] | [.]], atomic: [], sets: [], maps: []})
            | if $static == {} and (keys - $rule.keys) == [] then empty else . end
          end
      end;
  def elements($rule):
    . as $current
    | ($static | hm_declared_array($p)) as $declared
    | [.[] | element($declared; $rule)]
    | hm_remove_emptied($p; $recorded; $static; $current);
  ($static | hm_rule($p; $recorded; $rules)) as $rule
  | if $rule.kind == "keep" or $rule.kind == "declared" then
      .
    elif $rule.kind == "leaf" then
      hm_remove_leaf($recorded)
    elif $rule.kind == "atomic" then
      hm_remove_atomic($recorded)
    elif $rule.kind == "set" then
      hm_remove_set($p; $recorded; $static; $rule.rule)
    elif $rule.kind == "map" then
      elements($rule.rule)
    else
      fields
    end;

# $previous and $static arrive through --slurpfile, each as a single value,
# since a command-line argument can exceed the size limit of the command
# line. A file whose whole content goes is left empty.
$previous[0] as $previous
| $static[0] as $static
| . as $file
| [hm_remove([]; $previous; $static; $rules)]
| if . == [] then ($file | if type == "array" then [] else {} end) else .[0] end
