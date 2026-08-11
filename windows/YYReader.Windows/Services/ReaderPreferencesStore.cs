using System.Text.Json;
using YYReader.Windows.Core.Models;

namespace YYReader.Windows.Services;

public sealed class ReaderPreferencesStore
{
    private readonly string _path;

    public ReaderPreferencesStore()
    {
        var directory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "YYReader");
        Directory.CreateDirectory(directory);
        _path = Path.Combine(directory, "reader-preferences.json");
    }

    public async Task<ReaderPreferences> LoadAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            await using var stream = File.OpenRead(_path);
            return (await JsonSerializer.DeserializeAsync<ReaderPreferences>(stream, cancellationToken: cancellationToken).ConfigureAwait(false))?.Normalized()
                ?? ReaderPreferences.Defaults;
        }
        catch (FileNotFoundException)
        {
            return ReaderPreferences.Defaults;
        }
        catch (JsonException)
        {
            return ReaderPreferences.Defaults;
        }
        catch (IOException)
        {
            return ReaderPreferences.Defaults;
        }
    }

    public async Task SaveAsync(ReaderPreferences preferences, CancellationToken cancellationToken = default)
    {
        var temporaryPath = $"{_path}.{Guid.NewGuid():N}.tmp";
        try
        {
            await using (var stream = File.Create(temporaryPath))
            {
                await JsonSerializer.SerializeAsync(stream, preferences.Normalized(), cancellationToken: cancellationToken).ConfigureAwait(false);
            }
            File.Move(temporaryPath, _path, true);
        }
        finally
        {
            if (File.Exists(temporaryPath)) File.Delete(temporaryPath);
        }
    }
}
