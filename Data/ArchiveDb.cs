using Microsoft.EntityFrameworkCore;

namespace iSupportArchiveV2.Data;

/// <summary>A ticket from the old iSupport system (dbo.Incidents).</summary>
public sealed class Incident
{
    public string TicketNumber { get; set; } = "";
    public string? Status { get; set; }
    public DateTime? CreatedDate { get; set; }
    /// <summary>The customer's email address (jdoe@richland2.org).</summary>
    public string? CreatedBy { get; set; }
    public DateTime? ClosedDate { get; set; }
    public string? ClosedBy { get; set; }
    public string? CategoryName { get; set; }
    public string? Campus { get; set; }
    public string? Room { get; set; }
    public string? Problem { get; set; }
    public string? Resolution { get; set; }
    public string? AssignedTo { get; set; }
    public string? CustEmail { get; set; }
    public string? CustCampus { get; set; }
}

/// <summary>A comment on a ticket (dbo.Comments, which has no key).</summary>
public sealed class Comment
{
    public string TicketNumber { get; set; } = "";
    public string? Visibility { get; set; }
    public DateTime? CreatedDate { get; set; }
    public string? CreatedBy { get; set; }
    public string? Entry { get; set; }
}

/// <summary>A file attached to a ticket (dbo.Files, which has no key: a file is its ticket number and name).</summary>
public sealed class Attachment
{
    public string TicketNumber { get; set; } = "";
    public DateTime? CreatedDate { get; set; }
    public string FileType { get; set; } = "";
    public string FileName { get; set; } = "";
    public byte[] FileData { get; set; } = [];
}

/// <summary>
/// iSupport_Archive on sql1, read only: the tables are the old system's, never migrated, and saving is refused.
/// </summary>
public sealed class ArchiveDb(DbContextOptions<ArchiveDb> options) : DbContext(options)
{
    public DbSet<Incident> Incidents => Set<Incident>();
    public DbSet<Comment> Comments => Set<Comment>();
    public DbSet<Attachment> Files => Set<Attachment>();

    protected override void OnModelCreating(ModelBuilder model)
    {
        model.Entity<Incident>(e =>
        {
            e.ToTable("Incidents");
            e.HasKey(i => i.TicketNumber);
            e.Property(i => i.TicketNumber).HasMaxLength(10);
            e.Property(i => i.CreatedDate).HasColumnType("datetime");
            e.Property(i => i.ClosedDate).HasColumnType("datetime");
        });
        model.Entity<Comment>(e =>
        {
            e.ToTable("Comments");
            e.HasNoKey();
            e.Property(c => c.TicketNumber).HasMaxLength(10);
            e.Property(c => c.CreatedDate).HasColumnType("datetime");
        });
        model.Entity<Attachment>(e =>
        {
            e.ToTable("Files");
            e.HasNoKey();
            e.Property(f => f.TicketNumber).HasMaxLength(10);
            e.Property(f => f.CreatedDate).HasColumnType("datetime");
            e.Property(f => f.FileData).HasColumnType("image");
        });
    }

    public override int SaveChanges(bool acceptAllChangesOnSuccess) =>
        throw new InvalidOperationException("iSupport_Archive is read only.");

    public override Task<int> SaveChangesAsync(bool acceptAllChangesOnSuccess, CancellationToken cancellationToken = default) =>
        throw new InvalidOperationException("iSupport_Archive is read only.");
}
