import json, jsonschema
doc = json.load(open('ar_out.json'))
schema = json.load(open('ar.json'))
def strip(o):
    if isinstance(o, dict):
        if 'pattern' in o and '\p{' in str(o['pattern']): o.pop('pattern')
        for v in o.values(): strip(v)
    elif isinstance(o, list):
        for v in o: strip(v)
strip(schema)
errs = sorted(jsonschema.Draft7Validator(schema).iter_errors({"assessment-results": doc}),
              key=lambda e: list(e.path))
print("validation errors:", len(errs))
for e in errs[:15]:
    print(" -", "/".join(str(x) for x in e.path), "::", e.message[:200])
