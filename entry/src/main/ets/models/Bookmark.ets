export class Bookmark {
  id: number = 0
  workId: number = 0
  workType: string = ''
  tags: string[] = []
  restrict: string = 'public'
  createDate: string = ''

  constructor(options: Partial<Bookmark> = {}) {
    this.id = options.id ?? 0
    this.workId = options.workId ?? 0
    this.workType = options.workType ?? ''
    this.tags = options.tags ?? []
    this.restrict = options.restrict ?? 'public'
    this.createDate = options.createDate ?? ''
  }
}
