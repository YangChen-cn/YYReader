using Microsoft.VisualStudio.TestTools.UnitTesting;
using YYReader.Windows.Core.Sync;

namespace YYReader.Windows.Tests;

[TestClass]
public sealed class SyncRecoveryGuardTests
{
    [TestMethod]
    public async Task WatchdogAbandonsHungOperationAndAllowsRetry()
    {
        var watchdog = new RecoverableSyncWatchdog();
        var never = new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously);

        var timedOut = await watchdog.RunAsync(_ => never.Task, TimeSpan.FromMilliseconds(30));
        var retried = await watchdog.RunAsync(_ => Task.FromResult(42), TimeSpan.FromSeconds(1));

        Assert.AreEqual(WatchdogStatus.TimedOut, timedOut.Status);
        Assert.AreEqual(WatchdogStatus.Completed, retried.Status);
        Assert.AreEqual(42, retried.Value);
    }

    [TestMethod]
    public async Task WatchdogRejectsDuplicateOperationWhileCurrentOneIsHealthy()
    {
        var watchdog = new RecoverableSyncWatchdog();
        var release = new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously);
        var first = watchdog.RunAsync(_ => release.Task, TimeSpan.FromSeconds(1));

        var duplicate = await watchdog.RunAsync(_ => Task.FromResult(2), TimeSpan.FromSeconds(1));
        release.SetResult(1);
        var completed = await first;

        Assert.AreEqual(WatchdogStatus.Busy, duplicate.Status);
        Assert.AreEqual(WatchdogStatus.Completed, completed.Status);
    }

    [TestMethod]
    public async Task WatchdogReleasesSlotWhenOperationThrowsSynchronously()
    {
        var watchdog = new RecoverableSyncWatchdog();

        await Assert.ThrowsExceptionAsync<InvalidOperationException>(() =>
            watchdog.RunAsync<int>(_ => throw new InvalidOperationException("boom"), TimeSpan.FromSeconds(1)));
        var retried = await watchdog.RunAsync(_ => Task.FromResult(7), TimeSpan.FromSeconds(1));

        Assert.AreEqual(WatchdogStatus.Completed, retried.Status);
        Assert.AreEqual(7, retried.Value);
    }

    [TestMethod]
    public void ProbeGuardPreventsDuplicatesAndHonorsAutomaticBackoff()
    {
        var guard = new SingleFlightProbeGuard();
        var now = DateTimeOffset.UtcNow;

        Assert.IsTrue(guard.TryBegin(now));
        Assert.IsFalse(guard.TryBegin(now));
        guard.DelayAutomaticProbesUntil(now.AddMinutes(2));
        guard.Complete();
        Assert.IsFalse(guard.TryBegin(now.AddMinutes(1)));
        Assert.IsTrue(guard.TryBegin(now.AddMinutes(1), bypassBackoff: true));
    }
}
