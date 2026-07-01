import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { buffer } from '@kit.ArkTS';

export class CryptoUtils {
  static md5(input: string): string {
    let md = cryptoFramework.createMd('MD5');
    let data = new Uint8Array(buffer.from(input, 'utf-8').buffer);
    md.updateSync({ data: data });
    let result = md.digestSync();
    let output = '';
    for (let i = 0; i < result.data.length; i++) {
      let hex = result.data[i].toString(16);
      if (hex.length < 2) {
        hex = '0' + hex;
      }
      output += hex;
    }
    return output;
  }

  static getIsoDate(): string {
    let now = new Date();
    let year = now.getUTCFullYear().toString();
    let month = (now.getUTCMonth() + 1).toString().padStart(2, '0');
    let day = now.getUTCDate().toString().padStart(2, '0');
    let hour = now.getUTCHours().toString().padStart(2, '0');
    let minute = now.getUTCMinutes().toString().padStart(2, '0');
    let second = now.getUTCSeconds().toString().padStart(2, '0');
    return year + '-' + month + '-' + day + 'T' + hour + ':' + minute + ':' + second + '+00:00';
  }
}
