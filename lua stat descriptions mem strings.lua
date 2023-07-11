local t, i = {}, 1
for addr = 0x56B76C, 0x56C180, 4 do
	local str = mem.string(mem.u4[addr])
	str = str:sub(1, math.min(100, str:len()))
	t[i] = string.format("[%d, 0x%X] %s", i - 1, addr, str)
	i = i + 1
end
io.save("mem strings.txt", table.concat(t, "\r\n")