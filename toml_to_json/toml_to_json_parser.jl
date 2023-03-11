using PEG
using Dates

toml ="""
# This is a TOML document

title = "TOML Example"

[owner]
name = "Tom Preston-Werner"
dob = 1979-05-27T07:32:00-08:00

[database]
enabled = true
ports = [ 8000, 8001, 8002 ]
data = [ ["delta", "phi"], [3.14] ]
temp_targets = { cpu = 79.5, case = 72.0 }

[servers]

[servers.alpha]
ip = "10.0.0.1"
role = "frontend"

[servers.beta]
ip = "10.0.0.2"
role = "backend"
"""

@rule document = block[+] |> v -> filter(!isnothing, v) |> d -> merge(d...)
@rule block    = comment, chunk, pair, crlf
@rule crlf     = r"\r?\n"p |> x -> nothing
@rule comment  = r"#"p & r"[^\n]*"p    > (_,c)     -> nothing
@rule chunk    = head & crlf & pair[*] > (h,_,arr) -> Dict(h => isempty(arr) ? [] : merge(arr...))
@rule head     = "[" & key & "]"       > (_,k,_)   -> k
@rule pair     = key & r"="p & value   > (k,_,v)   -> Dict(k => v)
@rule key      = r"(\w|\.)+"w
@rule value    = string, datetime, date, boolean, array, object, number

@rule string   = r"\"[^\"]*\""p |> s -> replace(s, "\"" => "")
@rule number   = r"-?(0|[1-9]\d*)(\.\d+)?"p |> Meta.parse
@rule boolean  = r"true|false"w             |> Meta.parse
@rule date =
    r"\d{4}" & date_sep & r"\d{2}" & date_sep & r"\d{2}" >
    (y,_,m,_,d) -> Date("$y-$m-$d")
@rule date_sep = ("-", "/")[:?]
@rule datetime =
    date & r"\s?T?" & r"\d{2}" & r"\:?" & r"\d{2}" & r"\:?" & r"(\d{2})?" & r"(-\d{2}\:\d{2})?"p >
    (date,_,h,_,m,_,s,z) -> DateTime("$(date)T$h:$m:$s")

@rule array    = r"\["p & (value & (r"\,"p & value)[*] > comma_format)[:?] & r"\]"p |> (a) -> isempty(a[2]) ? [] : a[2][1]
@rule object   = r"\{"p & (pair  & (r"\,"p & pair)[*] > comma_format) & r"\}"p > (_, p, _) -> merge(p...)

comma_format(head, others) = [head, map(x -> x[2], others)...]

using Test
@testset "basic" begin
    @test parse_whole(crlf, "\n") |> isnothing
    @test parse_whole(string, "\"TOML Example\"") == "TOML Example"
    @test parse_whole(head, "[owner]") == "owner"
    @test parse_whole(datetime, "1979-05-27T07:32:00-08:00") |> typeof == DateTime
    @test parse_whole(boolean, "true") == true
    @test parse_whole(number, "8000") == 8000
    @test parse_whole(key, "servers.alpha") == "servers.alpha"
end

@testset "combination" begin
    @test parse_whole(pair, "name = \"Tom Preston-Werner\"")   == Dict("name" => "Tom Preston-Werner")
    @test parse_whole(pair, "dob = 1979-05-27T07:32:00-08:00") == Dict("dob" => DateTime("1979-05-27T07:32:00"))
    @test parse_whole(value, "1979-05-27T07:32:00-08:00") |> !isnothing
    @test parse_whole(value, "\"TOML Example\"") |> !isnothing
    @test parse_whole(value, "8000") |> !isnothing
    @test parse_whole(array, "[ 8000, 8001, 8002 ]") == [8000, 8001, 8002]
    @test parse_whole(array, "[ [\"delta\", \"phi\"], [3.14] ]") |> typeof == Vector{Vector}
    @test parse_whole(object, "{ cpu = 79.5, case = 72.0 }") == Dict("cpu" => 79.5, "case" => 72.0)
end

@testset "block" begin
    @test parse_whole(comment, "# This is a TOML document") |> isnothing
    @test parse_whole(chunk, "[servers]\n") == Dict("servers" => [])
    @test parse_whole(chunk, """
    [owner]
    name = "Tom Preston-Werner"
    dob = 1979-05-27T07:32:00-08:00
    """) == Dict("owner" => Dict(
        "name" => "Tom Preston-Werner",
        "dob"  => DateTime("1979-05-27T07:32:00")
    ))
    @test parse_whole(chunk, """
    [database]
    enabled = true
    ports = [ 8000, 8001, 8002 ]
    data = [ ["delta", "phi"], [3.14] ]
    temp_targets = { cpu = 79.5, case = 72.0 }
    """) == Dict("database" => Dict(
        "enabled" => true,
        "ports"   => [8000, 8001, 8002],
        "data"    => [ ["delta", "phi"], [3.14] ],
        "temp_targets" => Dict(
            "cpu"  => 79.5,
            "case" => 72.0,
        ),
    ))
end

@testset "document" begin
    @test parse_whole(document, """
    [servers]

    [servers.alpha]
    ip = "10.0.0.1"
    role = "frontend"
    """) == Dict(
        "servers" => [],
        "servers.alpha" => Dict(
            "ip"   => "10.0.0.1",
            "role" => "frontend"
        )
    )
end

result = parse_whole(document, toml)
# == Dict{SubString{String}, Any} with 6 entries:
#    "servers"       => Any[]
#    "servers.beta"  => Dict{SubString{String}, String}("role"=>"backend", "ip"=>"10.0.0.2")
#    "owner"         => Dict{SubString{String}, Any}("name"=>"Tom Preston-Werner", "dob"=>DateTime("1979-05-27T07:32:00"))
#    "title"         => "TOML Example"
#    "servers.alpha" => Dict{SubString{String}, String}("role"=>"frontend", "ip"=>"10.0.0.1")
#    "database"      => Dict{SubString{String}, Any}("data"=>Vector[["delta", "phi"], [3.14]], "enabled"=>true, "ports"=>[8000, 8001, 8002], "temp_targets…


using JSON
json(result)
# => {
#   "servers": [],
#   "servers.beta": {
#     "role": "backend",
#     "ip": "10.0.0.2"
#   },
#   "owner": {
#     "name": "Tom Preston-Werner",
#     "dob": "1979-05-27T07:32:00"
#   },
#   "title": "TOML Example",
#   "servers.alpha": {
#     "role": "frontend",
#     "ip": "10.0.0.1"
#   },
#   "database": {
#     "data": [
#       ["delta", "phi"],
#       [3.14]
#     ],
#     "enabled": true,
#     "ports": [8000, 8001, 8002],
#     "temp_targets": {
#       "cpu": 79.5,
#       "case": 72.0
#     }
#   }
# }
