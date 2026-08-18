miniaudio = {
	source = path.join(dependencies.basePath, "miniaudio"),
}

function miniaudio.import()
	miniaudio.includes()
end

function miniaudio.includes()
	includedirs {
		miniaudio.source
	}
end

function miniaudio.project()

end

table.insert(dependencies, miniaudio)
