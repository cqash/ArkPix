export interface DohAnswerOptions {
  name?: string
  type?: number
  TTL?: number
  data?: string
}

interface RawDohAnswer {
  name: string
  type: number
  TTL: number
  data: string
}

export class DohAnswer {
  name: string = ''
  type: number = 0
  TTL: number = 0
  data: string = ''

  constructor(options?: DohAnswerOptions) {
    if (options) {
      this.name = options.name ?? ''
      this.type = options.type ?? 0
      this.TTL = options.TTL ?? 0
      this.data = options.data ?? ''
    }
  }

  static fromJson(json: Object): DohAnswerOptions {
    let p = json as RawDohAnswer
    let opts: DohAnswerOptions = {
      name: p?.name ?? '',
      type: p?.type ?? 0,
      TTL: p?.TTL ?? 0,
      data: p?.data ?? ''
    }
    return opts
  }
}

export interface DohResponseOptions {
  Status?: number
  Answer?: DohAnswerOptions[]
}

interface RawDohResponse {
  Status: number
  Answer: RawDohAnswer[]
}

export class DohResponse {
  Status: number = 0
  Answer: DohAnswer[] = []

  constructor(options?: DohResponseOptions) {
    if (options) {
      this.Status = options.Status ?? 0
      this.Answer = (options.Answer ?? []).map((a: DohAnswerOptions): DohAnswer => new DohAnswer(a))
    }
  }

  static fromJson(json: Object): DohResponseOptions {
    let p = json as RawDohResponse
    let opts: DohResponseOptions = {
      Status: p?.Status ?? 0,
      Answer: p?.Answer ? p.Answer.map((a: RawDohAnswer): DohAnswerOptions => DohAnswer.fromJson(a)) : []
    }
    return opts
  }
}

export function parseDohResponse(body: string): string {
  try {
    let raw: Object = JSON.parse(body)
    let doh = new DohResponse(DohResponse.fromJson(raw))
    if (doh.Answer.length === 0) {
      return ''
    }
    let bestIp = ''
    let bestTtl = -1
    for (let i = 0; i < doh.Answer.length; i++) {
      let ans = doh.Answer[i]
      if (ans.type === 1) {
        let ip = ans.data
        if (isValidIPv4(ip) && ans.TTL > bestTtl) {
          bestTtl = ans.TTL
          bestIp = ip
        }
      }
    }
    return bestIp
  } catch (e) {
    console.error('Parse DoH response failed: ' + e)
    return ''
  }
}

function isValidIPv4(ip: string): boolean {
  let parts = ip.split('.')
  if (parts.length !== 4) {
    return false
  }
  for (let i = 0; i < parts.length; i++) {
    let num = Number(parts[i])
    if (Number.isNaN(num) || num < 0 || num > 255) {
      return false
    }
  }
  return true
}
