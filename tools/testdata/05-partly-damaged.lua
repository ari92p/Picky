-- TEST DATA: stress test: missing parts, broken orders (expected: no Lua errors, valid orders "Heil" and "OhneStatus" remain)
PickyDB = {
["stats"] = {
["picked"] = 5,
},
["orders"] = {
{
["name"] = "Heil",
["sender"] = "Heil",
["stamp"] = 1795338000,
["status"] = "done",
["time"] = 0.0,
["boxes"] = 1,
["tipTotal"] = 0,
["joinStamp"] = 1795338010,
["endStamp"] = 1795338050,
},
"kein Eintrag",
{
["status"] = "done",
},
{
["name"] = "OhneStatus",
["stamp"] = 1795341600,
},
},
["ui"] = {
["scale"] = 100,
},
["finder"] = {
["leaveDelay"] = 5,
},
["ad"] = {
},
["itemNames"] = {
},
}
