using System.Collections.ObjectModel;
using System.Collections.Specialized;
using System.ComponentModel;

namespace YYReader.Windows.Core.Collections;

public sealed class RangeObservableCollection<T> : ObservableCollection<T>
{
    public void AddRange(IEnumerable<T> values)
    {
        var additions = values.ToArray();
        if (additions.Length == 0) return;
        CheckReentrancy();
        var startIndex = Items.Count;
        foreach (var value in additions) Items.Add(value);
        OnPropertyChanged(new PropertyChangedEventArgs(nameof(Count)));
        OnPropertyChanged(new PropertyChangedEventArgs("Item[]"));
        OnCollectionChanged(new NotifyCollectionChangedEventArgs(NotifyCollectionChangedAction.Add, additions, startIndex));
    }

    public void ReplaceAll(IEnumerable<T> values)
    {
        CheckReentrancy();
        Items.Clear();
        foreach (var value in values) Items.Add(value);
        OnPropertyChanged(new PropertyChangedEventArgs(nameof(Count)));
        OnPropertyChanged(new PropertyChangedEventArgs("Item[]"));
        OnCollectionChanged(new NotifyCollectionChangedEventArgs(NotifyCollectionChangedAction.Reset));
    }
}
