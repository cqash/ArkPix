import { describe, it, expect } from '@ohos/hypium';
import { commentFromJson, parseCommentListPage } from '../main/ets/models/Comment';

export default function commentTest() {
  describe('CommentTest', () => {
    it('should_parse_basic_fields', 0, () => {
      let raw: Object = JSON.parse('{"id":123,"comment":"好看","date":"2026-07-01T10:00:00+09:00",' +
        '"user":{"id":456,"name":"画师A","account":"artist_a","profile_image_urls":{"medium":"https://i.pximg.net/a.jpg"}}}')
      let comment = commentFromJson(raw)
      expect(comment.id).assertEqual(123)
      expect(comment.comment).assertEqual('好看')
      expect(comment.date).assertEqual('2026-07-01T10:00:00+09:00')
      expect(comment.user.id).assertEqual(456)
      expect(comment.user.name).assertEqual('画师A')
      expect(comment.user.account).assertEqual('artist_a')
      expect(comment.user.profileImageUrls.medium).assertEqual('https://i.pximg.net/a.jpg')
      expect(comment.parentCommentId).assertEqual(0)
      expect(comment.replyToUserName).assertEqual('')
      expect(comment.hasReplies).assertFalse()
      expect(comment.hasStamp).assertFalse()
    })

    it('should_parse_parent_comment_into_reply_to_user_name', 0, () => {
      let raw: Object = JSON.parse('{"id":200,"comment":"回复内容","date":"2026-07-02",' +
        '"user":{"id":1,"name":"回复者","account":"r","profile_image_urls":{"medium":""}},' +
        '"parent_comment":{"id":100,"user":{"id":2,"name":"被回复者"}}}')
      let comment = commentFromJson(raw)
      expect(comment.parentCommentId).assertEqual(100)
      expect(comment.replyToUserName).assertEqual('被回复者')
    })

    it('should_default_missing_fields', 0, () => {
      let raw: Object = JSON.parse('{}')
      let comment = commentFromJson(raw)
      expect(comment.id).assertEqual(0)
      expect(comment.comment).assertEqual('')
      expect(comment.date).assertEqual('')
      expect(comment.user.id).assertEqual(0)
      expect(comment.parentCommentId).assertEqual(0)
      expect(comment.replyToUserName).assertEqual('')
      expect(comment.hasReplies).assertFalse()
      expect(comment.hasStamp).assertFalse()
    })

    it('should_detect_stamp_and_has_replies', 0, () => {
      let raw: Object = JSON.parse('{"id":300,"comment":"","date":"2026-07-03",' +
        '"user":{"id":1,"name":"u","account":"a","profile_image_urls":{"medium":""}},' +
        '"has_replies":true,"stamp":{"stamp_id":1001}}')
      let comment = commentFromJson(raw)
      expect(comment.hasReplies).assertTrue()
      expect(comment.hasStamp).assertTrue()
      expect(comment.comment).assertEqual('')
    })

    it('should_parse_comment_list_page', 0, () => {
      let raw: Object = JSON.parse('{"comments":[{"id":1,"comment":"a","date":"d",' +
        '"user":{"id":1,"name":"u","account":"a","profile_image_urls":{"medium":""}}}],' +
        '"next_url":"https://app-api.pixiv.net/v3/illust/comments?cursor=abc"}')
      let page = parseCommentListPage(raw)
      expect(page.comments.length).assertEqual(1)
      expect(page.comments[0].id).assertEqual(1)
      expect(page.nextUrl).assertEqual('https://app-api.pixiv.net/v3/illust/comments?cursor=abc')
    })

    it('should_handle_null_next_url', 0, () => {
      let raw: Object = JSON.parse('{"comments":[],"next_url":null}')
      let page = parseCommentListPage(raw)
      expect(page.comments.length).assertEqual(0)
      expect(page.nextUrl).assertEqual('')
    })
  })
}
