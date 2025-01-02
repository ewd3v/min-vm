export const parse = (settings) => {
    // Prevent mutations to the original dictionary
    settings = structuredClone(settings || {})

    settings.zstdLevel = settings.zstdLevel || 22

    return settings
}
