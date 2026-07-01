export class MuteItem {
  type: string = 'tag'
  value: string = ''
  userId: number = 0
  timestamp: number = Date.now()

  constructor(options: Partial<MuteItem> = {}) {
    this.type = options.type ?? 'tag'
    this.value = options.value ?? ''
    this.userId = options.userId ?? 0
    this.timestamp = options.timestamp ?? Date.now()
  }
}
