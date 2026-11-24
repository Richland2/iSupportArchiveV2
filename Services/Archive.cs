using System.Security.Claims;
using iSupportArchiveV2.Data;
using Microsoft.EntityFrameworkCore;
using Telerik.DataSource;
using Telerik.DataSource.Extensions;

namespace iSupportArchiveV2.Services;

/// <summary>Who's looking: their account name (cn) and whether they're staff (see every ticket).</summary>
public sealed record Viewer(string Cn, bool IsStaff)
{
    /// <summary>Tickets store the customer as an email address (jdoe@richland2.org): theirs start with "cn@".</summary>
    public bool IsCustomer(string? createdBy) =>
        createdBy is not null && createdBy.StartsWith(Cn + "@", StringComparison.OrdinalIgnoreCase);

    public bool CanSee(Incident? ticket) => ticket is not null && (IsStaff || IsCustomer(ticket.CreatedBy));
}

/// <summary>One row of the ticket list.</summary>
public sealed class TicketRow
{
    public string TicketNumber { get; set; } = "";
    public int AttachmentCount { get; set; }
    public DateTime? CreatedDate { get; set; }
    public DateTime? ClosedDate { get; set; }
    public string? CreatedBy { get; set; }
    public string? Problem { get; set; }
    public string? Resolution { get; set; }
    public string? AssignedTo { get; set; }
}

/// <summary>An attachment without its contents (the list never loads the files themselves).</summary>
public sealed record AttachmentRow(string TicketNumber, string FileName, string FileType, DateTime? CreatedDate);

/// <summary>
/// The archive, as the current site shows it: staff (the do_it_staff AD group) see every ticket; everyone else sees
/// only tickets they opened, and can't open anyone else's by guessing a number. Everything is read only.
/// </summary>
public sealed class Archive(IDbContextFactory<ArchiveDb> dbs, StaffGroup staff)
{
    /// <summary>The signed-in (or impersonated) user.</summary>
    public async Task<Viewer> ViewerAsync(ClaimsPrincipal user)
    {
        var name = user.Identity?.Name ?? "";
        var cn = name[(name.IndexOf('\\') + 1)..];
        return new Viewer(cn, await staff.ContainsAsync(cn));
    }

    /// <summary>A page of the ticket list, filtered, sorted and paged in SQL (the grid's request).</summary>
    public async Task<DataSourceResult> ReadTicketsAsync(Viewer viewer, DataSourceRequest request)
    {
        await using var db = await dbs.CreateDbContextAsync();
        var tickets = db.Incidents.AsNoTracking();
        if (!viewer.IsStaff)
        {
            var prefix = viewer.Cn + "@";
            tickets = tickets.Where(i => i.CreatedBy!.StartsWith(prefix));
        }
        var rows = tickets.Select(i => new TicketRow
        {
            TicketNumber = i.TicketNumber,
            AttachmentCount = db.Files.Count(f => f.TicketNumber == i.TicketNumber),
            CreatedDate = i.CreatedDate,
            ClosedDate = i.ClosedDate,
            CreatedBy = i.CreatedBy,
            Problem = i.Problem,
            Resolution = i.Resolution,
            AssignedTo = i.AssignedTo,
        });
        // newest first until the user sorts
        if (request.Sorts is not { Count: > 0 })
            rows = rows.OrderByDescending(r => r.CreatedDate).ThenByDescending(r => r.TicketNumber);
        return await rows.ToDataSourceResultAsync(request);
    }

    /// <summary>The ticket, or null when it doesn't exist or isn't the viewer's to see.</summary>
    public async Task<Incident?> GetTicketAsync(Viewer viewer, string number)
    {
        if (string.IsNullOrWhiteSpace(number)) return null;
        await using var db = await dbs.CreateDbContextAsync();
        var ticket = await db.Incidents.AsNoTracking().FirstOrDefaultAsync(i => i.TicketNumber == number);
        return viewer.CanSee(ticket) ? ticket : null;
    }

    public async Task<List<AttachmentRow>> GetAttachmentsAsync(string number)
    {
        await using var db = await dbs.CreateDbContextAsync();
        return await db.Files.Where(f => f.TicketNumber == number)
            .OrderBy(f => f.CreatedDate).ThenBy(f => f.FileName)
            .Select(f => new AttachmentRow(f.TicketNumber, f.FileName, f.FileType, f.CreatedDate))
            .ToListAsync();
    }

    public async Task<List<Comment>> GetCommentsAsync(string number)
    {
        await using var db = await dbs.CreateDbContextAsync();
        return await db.Comments.Where(c => c.TicketNumber == number).OrderBy(c => c.CreatedDate).ToListAsync();
    }

    /// <summary>One attachment's contents, only when the viewer may see its ticket.</summary>
    public async Task<Attachment?> GetAttachmentAsync(Viewer viewer, string number, string fileName)
    {
        if (await GetTicketAsync(viewer, number) is null) return null;
        await using var db = await dbs.CreateDbContextAsync();
        return await db.Files.FirstOrDefaultAsync(f => f.TicketNumber == number && f.FileName == fileName);
    }
}
