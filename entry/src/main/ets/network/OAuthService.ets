import { http } from '@kit.NetworkKit';
import { HttpClient } from './HttpClient';
import { PixivEndpoints } from './PixivEndpoints';
import { Constants } from '../utils/Constants';
import { CryptoUtils } from '../utils/CryptoUtils';
import { authInterceptor } from './AuthInterceptor';

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

export class OAuthService {
  private static instance: OAuthService
  private httpClient: HttpClient

  private constructor() {
    this.httpClient = HttpClient.getInstance()
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

    let response = await this.httpClient.post(PixivEndpoints.OAUTH_TOKEN_URL, body, {
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': Constants.USER_AGENT,
      'X-Client-Time': CryptoUtils.getIsoDate(),
      'X-Client-Hash': CryptoUtils.md5(CryptoUtils.getIsoDate() + Constants.HASH_SALT)
    })

    let result = JSON.parse(String(response.result)) as TokenResponse
    authInterceptor.setTokens(result.access_token, result.refresh_token)
    return result
  }

  async refreshToken(refreshToken: string): Promise<TokenResponse> {
    // 刷新必须使用与签发时相同的 client 凭证（exchangeToken 用 CLIENT_ID），
    // 否则服务端按 invalid_client 返回 400，导致刷新永远失败（历史"掉登录"根因）
    let body = 'grant_type=refresh_token' +
      '&refresh_token=' + refreshToken +
      '&client_id=' + Constants.CLIENT_ID +
      '&client_secret=' + Constants.CLIENT_SECRET

    // 网络层异常（超时/断网）归类为临时错误，不做登出处理
    let response: http.HttpResponse
    try {
      response = await this.httpClient.post(PixivEndpoints.OAUTH_TOKEN_URL, body, {
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': Constants.USER_AGENT,
        'X-Client-Time': CryptoUtils.getIsoDate(),
        'X-Client-Hash': CryptoUtils.md5(CryptoUtils.getIsoDate() + Constants.HASH_SALT)
      })
    } catch (e) {
      throw new NetworkError('刷新 token 网络请求失败: ' + e)
    }

    if (response.responseCode !== 200) {
      if (response.responseCode === 400 || response.responseCode === 401 || response.responseCode === 403) {
        throw new CredentialInvalidError('登录凭证已被服务端拒绝 (HTTP ' + response.responseCode + ')')
      }
      throw new NetworkError('刷新 token 服务器错误 (HTTP ' + response.responseCode + ')')
    }

    let raw: RawTokenResponse
    try {
      raw = JSON.parse(String(response.result)) as RawTokenResponse
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
}

export const oauthService = OAuthService.getInstance()
