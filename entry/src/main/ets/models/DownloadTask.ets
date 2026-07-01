export class DownloadTask {
  id: string = ''
  illustId: number = 0
  pageIndex: number = 0
  imageUrl: string = ''
  localPath: string = ''
  status: string = 'pending'
  progress: number = 0
  timestamp: number = Date.now()

  constructor(options: Partial<DownloadTask> = {}) {
    this.id = options.id ?? ''
    this.illustId = options.illustId ?? 0
    this.pageIndex = options.pageIndex ?? 0
    this.imageUrl = options.imageUrl ?? ''
    this.localPath = options.localPath ?? ''
    this.status = options.status ?? 'pending'
    this.progress = options.progress ?? 0
    this.timestamp = options.timestamp ?? Date.now()
  }
}
