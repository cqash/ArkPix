import { socket } from '@kit.NetworkKit';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PixivEndpoints } from './PixivEndpoints';
import { Constants } from '../utils/Constants';
import { CryptoUtils } from '../utils/CryptoUtils';
import { authInterceptor } from './AuthInterceptor';
import { relayClient, RelayRequestInput } from './RelayClient';
import { preferenceService } from '../services/PreferenceService';
import { hoster } from './Hoster';

/** 凭证失效：服务端明确拒绝 refresh token，必须重新登录 */
export class CredentialInvalidError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'CredentialInvalidError'
  }
}

/** 网络错误：临时故障（超时/5xx/解析失败），可重试，不应登出 */
export class NetworkError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'NetworkError'
  }
}

interface ProfileImageUrls {
  px_16x16?: string
  px_50x50?: string
  px_170x170?: string
}

interface UserInfo {
  id: string
  name: string
  account: string
  profile_image_urls: ProfileImageUrls
}

interface TokenResponse {
  access_token: string
  refresh_token: string
  user: UserInfo
}

/** 刷新接口原始响应（错误响应为合法 JSON 但无 token 字段） */
interface RawTokenResponse {
  access_token?: string
  refresh_token?: string
  user?: UserInfo
}

interface AuthHeaders {
  'Content-Type': string
  'User-Agent': string
  'X-Client-Time': string
  'X-Client-Hash': string
}

interface NoSniResponse {
  code: number
  body: string
}

export class OAuthService {
  private static instance: OAuthService

  private constructor() {
  }

  static getInstance(): OAuthService {
    if (!OAuthService.instance) {
      OAuthService.instance = new OAuthService()
    }
    return OAuthService.instance
  }

  getAuthUrl(codeChallenge: string): string {
    let url = PixivEndpoints.OAUTH_AUTH_URL +
      '?code_challenge=' + codeChallenge +
      '&code_challenge_method=S256&client=pixiv-android'
    return Constants.applyProxy(url)
  }

  async exchangeToken(code: string, codeVerifier: string): Promise<TokenResponse> {
    let body = 'grant_type=authorization_code' +
      '&code=' + code +
      '&code_verifier=' + codeVerifier +
      '&client_id=' + Constants.CLIENT_ID +
      '&client_secret=' + Constants.CLIENT_SECRET +
      '&redirect_uri=' + encodeURIComponent(Constants.REDIRECT_URI)

    let response = await this.postToken(body)
    if (response.code !== 200) {
      throw new Error('exchange token failed: ' + response.code + ' ' + response.body)
    }

    let result = JSON.parse(response.body) as TokenResponse
    authInterceptor.setTokens(result.access_token, result.refresh_token)
    return result
  }

  async refreshToken(refreshToken: string): Promise<TokenResponse> {
    // 刷新必须使用与签发时相同的 client 凭证（exchangeToken 用 CLIENT_ID），
    // 否则服务端按 invalid_client 返回 400，导致刷新永远失败（历史"掉登录"根因）
    let body = 'grant_type=refresh_token' +
      '&refresh_token=' + encodeURIComponent(refreshToken) +
      '&client_id=' + Constants.CLIENT_ID +
      '&client_secret=' + Constants.CLIENT_SECRET

    // 网络层异常（超时/断网）归类为临时错误，不做登出处理
    let response: NoSniResponse
    try {
      response = await this.postToken(body)
    } catch (e) {
      throw new NetworkError('刷新 token 网络请求失败: ' + e)
    }

    if (response.code !== 200) {
      console.error('OAuth refresh response: ' + response.code + ' ' + response.body)
      if (response.code === 400 || response.code === 401 || response.code === 403) {
        throw new CredentialInvalidError('登录凭证已被服务端拒绝 (HTTP ' + response.code + ')')
      }
      throw new NetworkError('刷新 token 服务器错误 (HTTP ' + response.code + ')')
    }

    let raw: RawTokenResponse
    try {
      raw = JSON.parse(response.body) as RawTokenResponse
    } catch (e) {
      throw new NetworkError('刷新 token 响应解析失败: ' + e)
    }

    // 有效性校验通过前不写回任何 token，杜绝错误 JSON 静默写坏登录态
    if (raw.access_token === undefined || raw.access_token.length === 0 ||
      raw.user === undefined || raw.user.id.length === 0) {
      throw new CredentialInvalidError('刷新 token 响应无效（缺少 access_token），请重新登录')
    }

    let result: TokenResponse = {
      access_token: raw.access_token,
      refresh_token: raw.refresh_token ?? refreshToken,
      user: raw.user
    }
    authInterceptor.setTokens(result.access_token, result.refresh_token)
    return result
  }

  private async postToken(body: string): Promise<NoSniResponse> {
    let authMode = Constants.normalizeMode(preferenceService.getString('auth_mode', Constants.MODE_STANDARD))
    if (Constants.isRelayMode(authMode)) {
      // relay 模式：旁路 TLSSocket no-SNI 路径，token 请求经中继转发。
      // 直接调 RelayClient 而非 HttpClient：避免 AuthInterceptor 向 token 端点注入
      // 过期 Pixiv Bearer 后把 4xx 误判为鉴权错误触发递归刷新。
      return this.postTokenViaRelay(body)
    }
    if (authMode === Constants.MODE_STANDARD) {
      // 标准模式：正常 HTTPS（走系统 DNS/VPN/代理），不用直连 IP hack
      return this.postTokenStandard(body)
    }
    return this.postTokenNoSni(body)
  }

  private async postTokenStandard(body: string): Promise<NoSniResponse> {
    let clientTime = CryptoUtils.getIsoDate()
    let header: Record<string, string> = {
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': Constants.USER_AGENT,
      'X-Client-Time': clientTime,
      'X-Client-Hash': CryptoUtils.md5(clientTime + Constants.HASH_SALT)
    }
    let req = http.createHttp()
    try {
      let resp = await req.request(Constants.BASE_OAUTH_URL + '/auth/token', {
        method: http.RequestMethod.POST,
        header: header,
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 20000
      })
      let out: NoSniResponse = { code: resp.responseCode, body: String(resp.result) }
      return out
    } finally {
      req.destroy()
    }
  }

  private async postTokenViaRelay(body: string): Promise<NoSniResponse> {
    let clientTime = CryptoUtils.getIsoDate()
    let header: Record<string, string> = {
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': Constants.USER_AGENT,
      'X-Client-Time': clientTime,
      'X-Client-Hash': CryptoUtils.md5(clientTime + Constants.HASH_SALT)
    }
    let input: RelayRequestInput = {
      url: Constants.BASE_OAUTH_URL + '/auth/token',
      method: http.RequestMethod.POST,
      header: header,
      body: body
    }
    let resp = await relayClient.relayRequest(input)
    let out: NoSniResponse = { code: resp.responseCode, body: String(resp.result) }
    return out
  }

  private async postTokenNoSni(body: string): Promise<NoSniResponse> {
    // 时间戳必须只取一次：time 与 hash 分两次取若跨秒会不一致，
    // Pixiv 校验失败返回 400，被误判为凭证失效导致误登出
    let clientTime = CryptoUtils.getIsoDate()
    let headerStr = 'Host: oauth.secure.pixiv.net\r\n' +
      'Content-Type: application/x-www-form-urlencoded\r\n' +
      'User-Agent: ' + Constants.USER_AGENT + '\r\n' +
      'X-Client-Time: ' + clientTime + '\r\n' +
      'X-Client-Hash: ' + CryptoUtils.md5(clientTime + Constants.HASH_SALT) + '\r\n' +
      'Content-Length: ' + body.length + '\r\n' +
      'Connection: close'
    // 优先用 Hoster 的 DoH 解析结果（与 LocalProxyServer 一致），硬编码 IP 可能已被运营商封锁
    let ip = Constants.DIRECT_IP_OAUTH
    let ips = hoster.resolveIps('oauth.secure.pixiv.net')
    if (ips.length > 0 && ips[0].length > 0) {
      ip = ips[0]
    }
    return this.doNoSniPost(ip, '/auth/token', headerStr, body)
  }

  private doNoSniPost(ip: string, path: string, headerStr: string, body: string): Promise<NoSniResponse> {
    return new Promise<NoSniResponse>((resolve, reject) => {
      let tls = socket.constructTLSSocketInstance()
      let acc = new Uint8Array(0)
      let settled = false
      let reqStr = 'POST ' + path + ' HTTP/1.1\r\n' + headerStr + '\r\n\r\n' + body
      // 兜底超时：直连 IP 被静默丢包时 connect/read 都会挂起，必须主动拒绝避免卡在"登录中"
      let timer = setTimeout(() => {
        if (settled) {
          return
        }
        settled = true
        try {
          tls.close()
        } catch (e) {
          console.error('tls close on timeout failed: ' + e)
        }
        reject(new Error('TLS request timeout'))
      }, 20000)
      let settle = (fn: () => void) => {
        clearTimeout(timer)
        fn()
      }
      tls.on('message', (info: socket.SocketMessageInfo) => {
        acc = this.concatBytesLocal(acc, new Uint8Array(info.message))
      })
      tls.on('close', () => {
        if (settled) {
          return
        }
        settled = true
        settle(() => resolve(this.parseHttpResponse(acc)))
      })
      tls.on('error', (err: BusinessError) => {
        if (settled) {
          return
        }
        settled = true
        settle(() => reject(new Error('TLS error: ' + JSON.stringify(err))))
      })
      // 部分设备上 TLSSocket 未显式 bind 直接 connect 会报 2303600 No bind socket，
      // 先绑定本地通配地址（端口 0 由系统分配）再连接
      let bindAddr: socket.NetAddress = { address: '0.0.0.0', family: 1, port: 0 }
      tls.bind(bindAddr).then(() => {
        return tls.connect({
          address: { address: ip, family: 1, port: 443 },
          secureOptions: {},
          timeout: 15000
        })
      }).then(() => {
        return tls.send(reqStr)
      }).catch((e: Object) => {
        if (!settled) {
          settled = true
          let err = e as BusinessError
          settle(() => reject(new Error('TLS connect/send failed: code=' + err.code + ' msg=' + err.message)))
        }
      })
    })
  }

  private concatBytesLocal(a: Uint8Array, b: Uint8Array): Uint8Array {
    let out = new Uint8Array(a.length + b.length)
    out.set(a, 0)
    out.set(b, a.length)
    return out
  }

  private bytesToString(bytes: Uint8Array): string {
    let chars: string[] = []
    for (let i = 0; i < bytes.length; i++) {
      chars.push(String.fromCharCode(bytes[i]))
    }
    return chars.join('')
  }

  private parseHttpResponse(bytes: Uint8Array): NoSniResponse {
    let str = this.bytesToString(bytes)
    let headerEnd = str.indexOf('\r\n\r\n')
    let head = headerEnd >= 0 ? str.substring(0, headerEnd) : str
    let body = headerEnd >= 0 ? str.substring(headerEnd + 4) : ''
    let lines = head.split('\r\n')
    let code = 0
    if (lines.length > 0) {
      let parts = lines[0].split(' ')
      if (parts.length >= 2) {
        let n = Number(parts[1])
        if (!Number.isNaN(n)) {
          code = Math.floor(n)
        }
      }
    }
    let result: NoSniResponse = { code: code, body: body }
    return result
  }
}

export const oauthService = OAuthService.getInstance()
