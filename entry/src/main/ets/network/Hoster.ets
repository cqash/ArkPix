import { rcp } from '@kit.RemoteCommunicationKit';
import { preferenceService } from '../services/PreferenceService';
import { parseDohResponse } from '../models/DohResponse';

const DOH_URL: string = 'https://1dot1dot1dot1.cloudflare-dns.com/dns-query';
const DOH_IPS: string[] = ['104.16.248.249', '104.16.249.249'];

export class Hoster {
  private static instance: Hoster
  private ipMap: Map<string, string> = new Map()

  private constructor() {}

  static getInstance(): Hoster {
    if (!Hoster.instance) {
      Hoster.instance = new Hoster()
    }
    return Hoster.instance
  }

  init(): void {
    let hosts: string[] = ['app-api.pixiv.net', 'oauth.secure.pixiv.net', 'i.pximg.net', 's.pximg.net']
    for (let i = 0; i < hosts.length; i++) {
      let host: string = hosts[i]
      let key: string = 'h_hoster_' + host
      let saved: string = preferenceService.getString(key, '')
      if (saved.length > 0) {
        this.ipMap.set(host, saved)
      } else {
        let fallback: string = this.getConstIp(host)
        if (fallback.length > 0) {
          this.ipMap.set(host, fallback)
        }
      }
    }
  }

  private getConstIp(host: string): string {
    if (host === 'app-api.pixiv.net') {
      return '210.140.139.155'
    }
    if (host === 'oauth.secure.pixiv.net') {
      return '210.140.139.155'
    }
    if (host === 'i.pximg.net') {
      return '210.140.139.133'
    }
    if (host === 's.pximg.net') {
      return '210.140.139.133'
    }
    return ''
  }

  async refreshAll(): Promise<void> {
    let hosts: string[] = ['app-api.pixiv.net', 'oauth.secure.pixiv.net', 'i.pximg.net', 's.pximg.net']
    for (let i = 0; i < hosts.length; i++) {
      try {
        await this.refreshHost(hosts[i])
      } catch (e) {
        console.error('Hoster refresh failed for ' + hosts[i] + ': ' + e)
      }
    }
  }

  private async refreshHost(host: string): Promise<void> {
    let dohSession: rcp.Session = rcp.createSession({
      requestConfiguration: {
        dns: {
          dnsRules: (dohHost: string, port: number): string[] => {
            if (dohHost === '1dot1dot1dot1.cloudflare-dns.com') {
              return DOH_IPS
            }
            return []
          }
        },
        transfer: {
          timeout: { connectMs: 15000, transferMs: 15000 }
        }
      }
    })
    try {
      let queryUrl: string = DOH_URL + '?name=' + host + '&type=A'
      let request: rcp.Request = new rcp.Request(queryUrl, 'GET')
      request.headers = { 'accept': 'application/dns-json' }
      let response: rcp.Response = await dohSession.fetch(request)
      if (response.statusCode === 200 && response.body) {
        let bodyStr: string = this.arrayBufferToString(response.body)
        let ip: string = parseDohResponse(bodyStr)
        if (ip.length > 0) {
          this.ipMap.set(host, ip)
          preferenceService.setString('h_hoster_' + host, ip)
        }
      }
    } catch (e) {
      console.error('DoH query failed for ' + host + ': ' + e)
    } finally {
      dohSession.close()
    }
  }

  resolveIps(host: string): string[] {
    let ip: string | undefined = this.ipMap.get(host)
    if (ip && ip.length > 0) {
      return [ip]
    }
    return []
  }

  private arrayBufferToString(buffer: ArrayBuffer): string {
    let bytes = new Uint8Array(buffer)
    let chars: string[] = []
    for (let i = 0; i < bytes.length; i++) {
      chars.push(String.fromCharCode(bytes[i]))
    }
    return chars.join('')
  }
}

export const hoster = Hoster.getInstance()
