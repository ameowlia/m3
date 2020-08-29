	"github.com/m3db/m3/src/dbnode/storage/namespace"
	"github.com/m3db/m3x/checked"
	"github.com/m3db/m3x/ident"
	"github.com/m3db/m3x/instrument"
	"github.com/m3db/m3x/pool"
	xtime "github.com/m3db/m3x/time"
// FileSetFileIdentifier contains all the information required to identify a FileSetFile
	// Required for snapshot files (index yes, data yes) and flush files (index yes, data no)
// DataWriterOpenOptions is the options struct for the Open method on the DataFileSetWriter
// that contains information specific to writing snapshot files
// DataFileSetWriter provides an unsynchronized writer for a TSDB file set
	Write(id ident.ID, tags ident.Tags, data checked.Bytes, checksum uint32) error
	WriteAll(id ident.ID, tags ident.Tags, data []checked.Bytes, checksum uint32) error
// DataFileSetReaderStatus describes the status of a file set reader

	Shard uint32
	Open  bool
// DataFileSetReader provides an unsynchronized reader for a TSDB file set
type DataFileSetReader interface {
	// Open opens the files for the given shard and version for reading
	// Status returns the status of the reader
	// ReadBloomFilter returns the bloom filter stored on disk in a container object that is safe
	// for concurrent use and has a Close() method for releasing resources when done.
	ReadBloomFilter() (*ManagedConcurrentBloomFilter, error)

	// Validate validates both the metadata and data and returns an error if either is corrupted
	// ValidateMetadata validates the data and returns an error if the data is corrupted
	ValidateMetadata() error

	// ValidateData validates the data and returns an error if the data is corrupted
	// Range returns the time range associated with data in the volume
	Range() xtime.Range

	// Entries returns the count of entries in the volume
	Entries() int

	// EntriesRead returns the position read into the volume

	// MetadataRead returns the position of metadata read into the volume
	MetadataRead() int
// DataFileSetSeeker provides an out of order reader for a TSDB file set
	// Open opens the files for the given shard and version for reading
	Open(namespace ident.ID, shard uint32, start time.Time) error
	SeekByID(id ident.ID) (data checked.Bytes, err error)
	SeekByIndexEntry(entry IndexEntry) (checked.Bytes, error)
	SeekIndexEntry(id ident.ID) (IndexEntry, error)
	// Range returns the time range associated with data in the volume
	// Entries returns the count of entries in the volume
	Entries() int

// ConcurrentDataFileSetSeeker is a limited interface that is returned when ConcurrentClone() is called on DataFileSetSeeker.
// The clones can be used together concurrently and share underlying resources. Clones are no
// longer usable once the original has been closed.
	// SeekByID is the same as in DataFileSetSeeker
	SeekByID(id ident.ID) (data checked.Bytes, err error)
	// SeekByIndexEntry is the same as in DataFileSetSeeker
	SeekByIndexEntry(entry IndexEntry) (checked.Bytes, error)
	// SeekIndexEntry is the same as in DataFileSetSeeker
	SeekIndexEntry(id ident.ID) (IndexEntry, error)
	// ConcurrentIDBloomFilter is the same as in DataFileSetSeeker
	Open(md namespace.Metadata) error
	// Borrow returns an open seeker for a given shard and block start time.
	// Return returns an open seeker for a given shard and block start time.
	// ConcurrentIDBloomFilter returns a concurrent ID bloom filter for a given
	// shard and block start time
	ConcurrentIDBloomFilter(shard uint32, start time.Time) (*ManagedConcurrentBloomFilter, error)
// DataBlockRetriever provides a block retriever for TSDB file sets
	// Open the block retriever to retrieve from a namespace
	Open(md namespace.Metadata) error
// RetrievableDataBlockSegmentReader is a retrievable block reader
	Snapshot IndexWriterSnapshotOptions
	// rate to use for the index bloom filter size and k hashes estimation
	// SetForceBloomFilterMmapMemory sets whether the bloom filters will be mmap'd.
	// ForceBloomFilterMmapMemory returns whether the bloom filters will be mmap'd.
// BlockRetrieverOptions represents the options for block retrieval
	// SetRequestPoolOptions sets the request pool options
	SetRequestPoolOptions(value pool.ObjectPoolOptions) BlockRetrieverOptions
	// RequestPoolOptions returns the request pool options
	RequestPoolOptions() pool.ObjectPoolOptions
	// SetBytesPool sets the bytes pool
	// BytesPool returns the bytes pool
	// SetSegmentReaderPool sets the segment reader pool
	SetSegmentReaderPool(value xio.SegmentReaderPool) BlockRetrieverOptions

	// SegmentReaderPool returns the segment reader pool
	SegmentReaderPool() xio.SegmentReaderPool

	// SetFetchConcurrency sets the fetch concurrency
	// FetchConcurrency returns the fetch concurrency
	// SetIdentifierPool sets the identifierPool
	// IdentifierPool returns the identifierPool