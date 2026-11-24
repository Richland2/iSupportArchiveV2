using System.DirectoryServices.AccountManagement;
using Microsoft.Extensions.Caching.Memory;

namespace iSupportArchiveV2.Services;

/// <summary>
/// Who's in the staff AD group (R2:Archive:StaffGroup, do_it_staff), including members of groups inside it, as the
/// current site checks. The whole membership is read once and remembered for 15 minutes, rather than asking AD on
/// every page. If AD can't be reached, nobody counts as staff (they see only their own tickets) and it's tried again
/// a minute later.
/// </summary>
public sealed class StaffGroup(IConfiguration configuration, IMemoryCache cache, ILogger<StaffGroup> log)
{
    private string GroupName => configuration["R2:Archive:StaffGroup"] is { Length: > 0 } name ? name : "do_it_staff";

    /// <summary>Whether the account (cn, without the domain) is in the group.</summary>
    public async Task<bool> ContainsAsync(string cn) =>
        !string.IsNullOrWhiteSpace(cn) && (await MembersAsync()).Contains(cn);

    private Task<HashSet<string>> MembersAsync() =>
        cache.GetOrCreateAsync("staff-group", entry =>
        {
            entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(15);
            try
            {
                return Task.FromResult(ReadMembers());
            }
            catch (Exception ex)
            {
                log.LogWarning(ex, "Couldn't read the {Group} AD group; nobody counts as staff for the next minute.", GroupName);
                entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(1);
                return Task.FromResult(new HashSet<string>(StringComparer.OrdinalIgnoreCase));
            }
        })!;

    private HashSet<string> ReadMembers()
    {
        using var domain = new PrincipalContext(ContextType.Domain, "richland2");
        using var group = GroupPrincipal.FindByIdentity(domain, IdentityType.SamAccountName, GroupName)
            ?? throw new InvalidOperationException($"There's no AD group named {GroupName}.");
        var members = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var member in group.GetMembers(recursive: true))
        {
            using (member)
                if (member is UserPrincipal { SamAccountName: { Length: > 0 } name }) members.Add(name);
        }
        return members;
    }
}
