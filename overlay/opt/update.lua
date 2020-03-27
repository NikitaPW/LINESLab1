#!/usr/bin/env lua

local socket = require("socket")
local http = require("socket.http")
local ftp = require("socket.ftp")
local url = require("socket.url")
local ltn12 = require("ltn12")

local lfs = require "lfs"

local blocksize = 512
local _ceil = math.ceil
local _tonumber = tonumber
local _ioOpen = io.open
local byte = string.byte


-- formats a number of seconds into human readable form
function nicetime(s)
    local l = "s"
    if s > 60 then
        s = s / 60
        l = "m"
        if s > 60 then
            s = s / 60
            l = "h"
            if s > 24 then
                s = s / 24
                l = "d" -- hmmm
            end
        end
    end
    if l == "s" then return string.format("%5.0f%s", s, l)
    else return string.format("%5.2f%s", s, l) end
end

-- formats a number of bytes into human readable form
function nicesize(b)
    local l = "B"
    if b > 1024 then
        b = b / 1024
        l = "KB"
        if b > 1024 then
            b = b / 1024
            l = "MB"
            if b > 1024 then
                b = b / 1024
                l = "GB" -- hmmm
            end
        end
    end
    return string.format("%7.2f%2s", b, l)
end

-- returns a string with the current state of the download
local remaining_s = "%s received, %s/s throughput, %2.0f%% done, %s remaining"
local elapsed_s =   "%s received, %s/s throughput, %s elapsed                "
function gauge(got, delta, size)
    local rate = got / delta
    if size and size >= 1 then
        return string.format(remaining_s, nicesize(got),  nicesize(rate),
            100*got/size, nicetime((size-got)/rate))
    else
        return string.format(elapsed_s, nicesize(got),
            nicesize(rate), nicetime(delta))
    end
end

-- creates a new instance of a receive_cb that saves to disk
-- kind of copied from luasocket's manual callback examples
function stats(size)
    local start = socket.gettime()
    local last = start
    local got = 0
    return function(chunk)
        -- elapsed time since start
        local current = socket.gettime()
        if chunk then
            -- total bytes received
            got = got + string.len(chunk)   
            -- not enough time for estimate
            if current - last > 1 then
                io.stderr:write("\r", gauge(got, current - start, size))
                io.stderr:flush()
                last = current
            end
        else
            -- close up
            io.stderr:write("\r", gauge(got, current - start), "\n")
        end
        return chunk
    end
end

-- determines the size of a http file
function gethttpsize(u)
    local r, c, h = http.request {method = "HEAD", url = u}
    if c == 200 then
        return tonumber(h["content-length"])
    end
end

-- downloads a file using the http protocol
function getbyhttp(u, file)
    local save = ltn12.sink.file(file or io.stdout)
    -- only print feedback if output is not stdout
    if file then save = ltn12.sink.chain(stats(gethttpsize(u)), save) end
    local r, c, h, s = http.request {url = u, sink = save }
    if c ~= 200 then io.stderr:write(s or c, "\n") end
end

-- downloads a file using the ftp protocol
function getbyftp(u, file)
    local save = ltn12.sink.file(file or io.stdout)
    -- only print feedback if output is not stdout
    -- and we don't know how big the file is
    if file then save = ltn12.sink.chain(stats(), save) end
    local gett = url.parse(u)
    gett.sink = save
    gett.type = "i"
    local ret, err = ftp.get(gett)
    if err then print(err) end
end


-- main program
local u = 'https://buildroot.org/downloads/buildroot-2020.02.tar.gz'
local name = 'update.tar.gz'
local fout = name and io.open(name, "w")
print('Update download started...')
getbyhttp(u, fout)
print('Download is successful!')

--local dir = lfs.currentdir()
print('Unpacking and writing...')
os.execute('tar -xzf ../update.tar.gz')
print('Update completed.')


