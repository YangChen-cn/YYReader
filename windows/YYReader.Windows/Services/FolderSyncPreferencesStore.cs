using System.Text.Json;

namespace YYReader.Windows.Services;

public sealed record FolderSyncPreferences(
    bool IsEnabled = false,
    string? FolderPath = null,
    DateTimeOffset? LastSyncAt = null);

public sealed class FolderSyncPreferencesStore
{
    private readonly string _path = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "YYReader",
        "folder-sync.json");

    public async Task<FolderSyncPreferences> LoadAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            if (!File.Exists(_path)) return new();
            await using var stream = File.OpenRead(_path);
            return await JsonSerializer.DeserializeAsync<FolderSyncPreferences>(stream, cancellationToken: cancellationToken)
                ?? new();
        }
        catch
        {
            return new();
        }
    }

    public async Task SaveAsync(FolderSyncPreferences preferences, CancellationToken cancellationToken = default)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        var temporary = $"{_path}.{Guid.NewGuid():N}.tmp";
        try
        {
            await using (var stream = File.Create(temporary))
            {
                await JsonSerializer.SerializeAsync(stream, preferences, cancellationToken: cancellationToken);
            }
            if (File.Exists(_path)) File.Replace(temporary, _path, null, true);
            else File.Move(temporary, _path);
        }
        finally
        {
            if (File.Exists(temporary)) File.Delete(temporary);
        }
    }
}
