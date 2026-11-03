// Сгенерировано: значки для каждого стиля оформления.
// Моно — тонкие контурные (Lucide), Стекло — скруглённые, Резкий — острые.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Значки приложения. Набор зависит от стиля, который выбран при запуске
/// (стиль меняется только после перезапуска, поэтому значки не «прыгают»).
class Ic {
  Ic._();

  /// mono, glass или sharp — ставится один раз при запуске.
  static String style = 'mono';

  static IconData get account_circle_outlined => switch (style) {
        'glass' => Icons.account_circle_outlined,
        'sharp' => Icons.account_circle_outlined,
        _ => LucideIcons.circleUser,
      };

  static IconData get add => switch (style) {
        'glass' => Icons.add_rounded,
        'sharp' => Icons.add_sharp,
        _ => LucideIcons.plus,
      };

  static IconData get add_circle_outline => switch (style) {
        'glass' => Icons.add_circle_outline,
        'sharp' => Icons.add_circle_outline,
        _ => LucideIcons.circlePlus,
      };

  static IconData get add_circle_outline_rounded => switch (style) {
        'glass' => Icons.add_circle_outline_rounded,
        'sharp' => Icons.add_circle_outline_sharp,
        _ => LucideIcons.circlePlus,
      };

  static IconData get album_outlined => switch (style) {
        'glass' => Icons.album_outlined,
        'sharp' => Icons.album_outlined,
        _ => LucideIcons.disc3,
      };

  static IconData get arrow_circle_down => switch (style) {
        'glass' => Icons.arrow_circle_down_rounded,
        'sharp' => Icons.arrow_circle_down_sharp,
        _ => LucideIcons.circleArrowDown,
      };

  static IconData get arrow_circle_down_outlined => switch (style) {
        'glass' => Icons.arrow_circle_down_outlined,
        'sharp' => Icons.arrow_circle_down_outlined,
        _ => LucideIcons.circleArrowDown,
      };

  static IconData get arrow_circle_down_rounded => switch (style) {
        'glass' => Icons.arrow_circle_down_rounded,
        'sharp' => Icons.arrow_circle_down_sharp,
        _ => Icons.arrow_circle_down_rounded,
      };

  static IconData get arrow_downward => switch (style) {
        'glass' => Icons.arrow_downward_rounded,
        'sharp' => Icons.arrow_downward_sharp,
        _ => LucideIcons.arrowDown,
      };

  static IconData get arrow_forward_rounded => switch (style) {
        'glass' => Icons.arrow_forward_rounded,
        'sharp' => Icons.arrow_forward_sharp,
        _ => LucideIcons.arrowRight,
      };

  static IconData get audio_file_outlined => switch (style) {
        'glass' => Icons.audio_file_outlined,
        'sharp' => Icons.audio_file_outlined,
        _ => Icons.audio_file_outlined,
      };

  static IconData get auto_awesome => switch (style) {
        'glass' => Icons.auto_awesome_rounded,
        'sharp' => Icons.auto_awesome_sharp,
        _ => LucideIcons.sparkles,
      };

  static IconData get autorenew => switch (style) {
        'glass' => Icons.autorenew_rounded,
        'sharp' => Icons.autorenew_sharp,
        _ => LucideIcons.refreshCw,
      };

  static IconData get block => switch (style) {
        'glass' => Icons.block_rounded,
        'sharp' => Icons.block_sharp,
        _ => LucideIcons.ban,
      };

  static IconData get cell_tower => switch (style) {
        'glass' => Icons.cell_tower_rounded,
        'sharp' => Icons.cell_tower_sharp,
        _ => LucideIcons.radioTower,
      };

  static IconData get check => switch (style) {
        'glass' => Icons.check_rounded,
        'sharp' => Icons.check_sharp,
        _ => LucideIcons.check,
      };

  static IconData get check_circle => switch (style) {
        'glass' => Icons.check_circle_rounded,
        'sharp' => Icons.check_circle_sharp,
        _ => Icons.check_circle_rounded,
      };

  static IconData get check_circle_outline => switch (style) {
        'glass' => Icons.check_circle_outline,
        'sharp' => Icons.check_circle_outline,
        _ => LucideIcons.circleCheck,
      };

  static IconData get check_circle_rounded => switch (style) {
        'glass' => Icons.check_circle_rounded,
        'sharp' => Icons.check_circle_sharp,
        _ => Icons.check_circle_rounded,
      };

  static IconData get checklist_rtl => switch (style) {
        'glass' => Icons.checklist_rtl_rounded,
        'sharp' => Icons.checklist_rtl_sharp,
        _ => LucideIcons.listChecks,
      };

  static IconData get chevron_right => switch (style) {
        'glass' => Icons.chevron_right_rounded,
        'sharp' => Icons.chevron_right_sharp,
        _ => LucideIcons.chevronRight,
      };

  static IconData get close => switch (style) {
        'glass' => Icons.close_rounded,
        'sharp' => Icons.close_sharp,
        _ => LucideIcons.x,
      };

  static IconData get close_fullscreen => switch (style) {
        'glass' => Icons.close_fullscreen_rounded,
        'sharp' => Icons.close_fullscreen_sharp,
        _ => LucideIcons.minimize2,
      };

  static IconData get close_rounded => switch (style) {
        'glass' => Icons.close_rounded,
        'sharp' => Icons.close_sharp,
        _ => LucideIcons.x,
      };

  static IconData get cloud_done_outlined => switch (style) {
        'glass' => Icons.cloud_done_outlined,
        'sharp' => Icons.cloud_done_outlined,
        _ => LucideIcons.cloudCheck,
      };

  static IconData get cloud_off => switch (style) {
        'glass' => Icons.cloud_off_rounded,
        'sharp' => Icons.cloud_off_sharp,
        _ => LucideIcons.cloudOff,
      };

  static IconData get cloud_outlined => switch (style) {
        'glass' => Icons.cloud_outlined,
        'sharp' => Icons.cloud_outlined,
        _ => LucideIcons.cloud,
      };

  static IconData get cloud_sync_outlined => switch (style) {
        'glass' => Icons.cloud_sync_outlined,
        'sharp' => Icons.cloud_sync_outlined,
        _ => LucideIcons.refreshCcwDot,
      };

  static IconData get cloud_upload_outlined => switch (style) {
        'glass' => Icons.cloud_upload_outlined,
        'sharp' => Icons.cloud_upload_outlined,
        _ => LucideIcons.cloudUpload,
      };

  static IconData get colorize => switch (style) {
        'glass' => Icons.colorize_rounded,
        'sharp' => Icons.colorize_sharp,
        _ => LucideIcons.pipette,
      };

  static IconData get crop_square_rounded => switch (style) {
        'glass' => Icons.crop_square_rounded,
        'sharp' => Icons.crop_square_sharp,
        _ => LucideIcons.square,
      };

  static IconData get delete_outline => switch (style) {
        'glass' => Icons.delete_outline,
        'sharp' => Icons.delete_outline,
        _ => Icons.delete_outline,
      };

  static IconData get deselect => switch (style) {
        'glass' => Icons.deselect_rounded,
        'sharp' => Icons.deselect_sharp,
        _ => Icons.deselect,
      };

  static IconData get dns_outlined => switch (style) {
        'glass' => Icons.dns_outlined,
        'sharp' => Icons.dns_outlined,
        _ => LucideIcons.server,
      };

  static IconData get download_done => switch (style) {
        'glass' => Icons.download_done_rounded,
        'sharp' => Icons.download_done_sharp,
        _ => LucideIcons.circleCheck,
      };

  static IconData get download_outlined => switch (style) {
        'glass' => Icons.download_outlined,
        'sharp' => Icons.download_outlined,
        _ => LucideIcons.download,
      };

  static IconData get drag_handle => switch (style) {
        'glass' => Icons.drag_handle_rounded,
        'sharp' => Icons.drag_handle_sharp,
        _ => LucideIcons.gripHorizontal,
      };

  static IconData get edit_note => switch (style) {
        'glass' => Icons.edit_note_rounded,
        'sharp' => Icons.edit_note_sharp,
        _ => LucideIcons.filePen,
      };

  static IconData get edit_outlined => switch (style) {
        'glass' => Icons.edit_outlined,
        'sharp' => Icons.edit_outlined,
        _ => LucideIcons.pencil,
      };

  static IconData get equalizer_rounded => switch (style) {
        'glass' => Icons.equalizer_rounded,
        'sharp' => Icons.equalizer_sharp,
        _ => Icons.equalizer_rounded,
      };

  static IconData get error_outline_rounded => switch (style) {
        'glass' => Icons.error_outline_rounded,
        'sharp' => Icons.error_outline_sharp,
        _ => LucideIcons.circleAlert,
      };

  static IconData get expand_less => switch (style) {
        'glass' => Icons.expand_less_rounded,
        'sharp' => Icons.expand_less_sharp,
        _ => LucideIcons.chevronUp,
      };

  static IconData get expand_more => switch (style) {
        'glass' => Icons.expand_more_rounded,
        'sharp' => Icons.expand_more_sharp,
        _ => LucideIcons.chevronDown,
      };

  static IconData get favorite => switch (style) {
        'glass' => Icons.favorite_rounded,
        'sharp' => Icons.favorite_sharp,
        _ => Icons.favorite_rounded,
      };

  static IconData get favorite_border => switch (style) {
        'glass' => Icons.favorite_border,
        'sharp' => Icons.favorite_border,
        _ => LucideIcons.heart,
      };

  static IconData get favorite_border_rounded => switch (style) {
        'glass' => Icons.favorite_border_rounded,
        'sharp' => Icons.favorite_border_sharp,
        _ => LucideIcons.heart,
      };

  static IconData get favorite_outline_rounded => switch (style) {
        'glass' => Icons.favorite_outline_rounded,
        'sharp' => Icons.favorite_outline_sharp,
        _ => LucideIcons.heart,
      };

  static IconData get favorite_rounded => switch (style) {
        'glass' => Icons.favorite_rounded,
        'sharp' => Icons.favorite_sharp,
        _ => Icons.favorite_rounded,
      };

  static IconData get filter_none_rounded => switch (style) {
        'glass' => Icons.filter_none_rounded,
        'sharp' => Icons.filter_none_sharp,
        _ => LucideIcons.copy,
      };

  static IconData get find_in_page_outlined => switch (style) {
        'glass' => Icons.find_in_page_outlined,
        'sharp' => Icons.find_in_page_outlined,
        _ => LucideIcons.fileSearch,
      };

  static IconData get folder_open_outlined => switch (style) {
        'glass' => Icons.folder_open_outlined,
        'sharp' => Icons.folder_open_outlined,
        _ => LucideIcons.folderOpen,
      };

  static IconData get folder_open_rounded => switch (style) {
        'glass' => Icons.folder_open_rounded,
        'sharp' => Icons.folder_open_sharp,
        _ => LucideIcons.folderOpen,
      };

  static IconData get graphic_eq => switch (style) {
        'glass' => Icons.graphic_eq_rounded,
        'sharp' => Icons.graphic_eq_sharp,
        _ => LucideIcons.audioLines,
      };

  static IconData get graphic_eq_rounded => switch (style) {
        'glass' => Icons.graphic_eq_rounded,
        'sharp' => Icons.graphic_eq_sharp,
        _ => Icons.graphic_eq_rounded,
      };

  static IconData get group_add_outlined => switch (style) {
        'glass' => Icons.group_add_outlined,
        'sharp' => Icons.group_add_outlined,
        _ => LucideIcons.userPlus,
      };

  static IconData get headphones => switch (style) {
        'glass' => Icons.headphones_rounded,
        'sharp' => Icons.headphones_sharp,
        _ => LucideIcons.headphones,
      };

  static IconData get headset_mic_outlined => switch (style) {
        'glass' => Icons.headset_mic_outlined,
        'sharp' => Icons.headset_mic_outlined,
        _ => LucideIcons.headset,
      };

  static IconData get heart_broken_outlined => switch (style) {
        'glass' => Icons.heart_broken_outlined,
        'sharp' => Icons.heart_broken_outlined,
        _ => LucideIcons.heartCrack,
      };

  static IconData get history => switch (style) {
        'glass' => Icons.history_rounded,
        'sharp' => Icons.history_sharp,
        _ => Icons.history,
      };

  static IconData get image_outlined => switch (style) {
        'glass' => Icons.image_outlined,
        'sharp' => Icons.image_outlined,
        _ => LucideIcons.image,
      };

  static IconData get insert_drive_file_outlined => switch (style) {
        'glass' => Icons.insert_drive_file_outlined,
        'sharp' => Icons.insert_drive_file_outlined,
        _ => LucideIcons.file,
      };

  static IconData get ios_share => switch (style) {
        'glass' => Icons.ios_share_rounded,
        'sharp' => Icons.ios_share_sharp,
        _ => LucideIcons.share,
      };

  static IconData get key_outlined => switch (style) {
        'glass' => Icons.key_outlined,
        'sharp' => Icons.key_outlined,
        _ => LucideIcons.keyRound,
      };

  static IconData get keyboard_arrow_down_rounded => switch (style) {
        'glass' => Icons.keyboard_arrow_down_rounded,
        'sharp' => Icons.keyboard_arrow_down_sharp,
        _ => LucideIcons.chevronDown,
      };

  static IconData get library_add_outlined => switch (style) {
        'glass' => Icons.library_add_outlined,
        'sharp' => Icons.library_add_outlined,
        _ => LucideIcons.libraryBig,
      };

  static IconData get library_music_outlined => switch (style) {
        'glass' => Icons.library_music_outlined,
        'sharp' => Icons.library_music_outlined,
        _ => LucideIcons.library,
      };

  static IconData get link => switch (style) {
        'glass' => Icons.link_rounded,
        'sharp' => Icons.link_sharp,
        _ => LucideIcons.link,
      };

  static IconData get content_paste_rounded => switch (style) {
        'glass' => Icons.content_paste_rounded,
        'sharp' => Icons.content_paste_sharp,
        _ => LucideIcons.clipboard,
      };

  static IconData get link_rounded => switch (style) {
        'glass' => Icons.link_rounded,
        'sharp' => Icons.link_sharp,
        _ => LucideIcons.link,
      };

  static IconData get login => switch (style) {
        'glass' => Icons.login_rounded,
        'sharp' => Icons.login_sharp,
        _ => LucideIcons.logIn,
      };

  static IconData get logout => switch (style) {
        'glass' => Icons.logout_rounded,
        'sharp' => Icons.logout_sharp,
        _ => LucideIcons.logOut,
      };

  static IconData get lyrics_outlined => switch (style) {
        'glass' => Icons.lyrics_outlined,
        'sharp' => Icons.lyrics_outlined,
        _ => LucideIcons.micVocal,
      };

  static IconData get manage_search => switch (style) {
        'glass' => Icons.manage_search_rounded,
        'sharp' => Icons.manage_search_sharp,
        _ => LucideIcons.fileSearch,
      };

  static IconData get more_vert => switch (style) {
        'glass' => Icons.more_vert_rounded,
        'sharp' => Icons.more_vert_sharp,
        _ => LucideIcons.ellipsisVertical,
      };

  static IconData get move_down => switch (style) {
        'glass' => Icons.move_down_rounded,
        'sharp' => Icons.move_down_sharp,
        _ => LucideIcons.arrowDownToLine,
      };

  static IconData get move_to_inbox_outlined => switch (style) {
        'glass' => Icons.move_to_inbox_outlined,
        'sharp' => Icons.move_to_inbox_outlined,
        _ => LucideIcons.inbox,
      };

  static IconData get network_check_rounded => switch (style) {
        'glass' => Icons.network_check_rounded,
        'sharp' => Icons.network_check_sharp,
        _ => LucideIcons.activity,
      };

  static IconData get notes => switch (style) {
        'glass' => Icons.notes_rounded,
        'sharp' => Icons.notes_sharp,
        _ => LucideIcons.notebookText,
      };

  static IconData get open_in_full => switch (style) {
        'glass' => Icons.open_in_full_rounded,
        'sharp' => Icons.open_in_full_sharp,
        _ => LucideIcons.maximize2,
      };

  static IconData get palette_outlined => switch (style) {
        'glass' => Icons.palette_outlined,
        'sharp' => Icons.palette_outlined,
        _ => LucideIcons.palette,
      };

  static IconData get pause => switch (style) {
        'glass' => Icons.pause_rounded,
        'sharp' => Icons.pause_sharp,
        _ => Icons.pause_rounded,
      };

  static IconData get pause_rounded => switch (style) {
        'glass' => Icons.pause_rounded,
        'sharp' => Icons.pause_sharp,
        _ => Icons.pause_rounded,
      };

  static IconData get people_outline => switch (style) {
        'glass' => Icons.people_outline,
        'sharp' => Icons.people_outline,
        _ => LucideIcons.users,
      };

  static IconData get person_add_alt_1 => switch (style) {
        'glass' => Icons.person_add_alt_1_rounded,
        'sharp' => Icons.person_add_alt_1_sharp,
        _ => LucideIcons.userPlus,
      };

  static IconData get person_off_outlined => switch (style) {
        'glass' => Icons.person_off_outlined,
        'sharp' => Icons.person_off_outlined,
        _ => LucideIcons.userX,
      };

  static IconData get person_outline => switch (style) {
        'glass' => Icons.person_outline,
        'sharp' => Icons.person_outline,
        _ => LucideIcons.user,
      };

  static IconData get photo_camera_outlined => switch (style) {
        'glass' => Icons.photo_camera_outlined,
        'sharp' => Icons.photo_camera_outlined,
        _ => LucideIcons.camera,
      };

  static IconData get play_arrow_rounded => switch (style) {
        'glass' => Icons.play_arrow_rounded,
        'sharp' => Icons.play_arrow_sharp,
        _ => Icons.play_arrow_rounded,
      };

  static IconData get play_circle_outline => switch (style) {
        'glass' => Icons.play_circle_outline,
        'sharp' => Icons.play_circle_outline,
        _ => LucideIcons.circlePlay,
      };

  static IconData get playlist_add => switch (style) {
        'glass' => Icons.playlist_add_rounded,
        'sharp' => Icons.playlist_add_sharp,
        _ => LucideIcons.listPlus,
      };

  static IconData get playlist_play => switch (style) {
        'glass' => Icons.playlist_play_rounded,
        'sharp' => Icons.playlist_play_sharp,
        _ => LucideIcons.listVideo,
      };

  static IconData get playlist_remove => switch (style) {
        'glass' => Icons.playlist_remove_rounded,
        'sharp' => Icons.playlist_remove_sharp,
        _ => LucideIcons.listX,
      };

  static IconData get power_settings_new => switch (style) {
        'glass' => Icons.power_settings_new_rounded,
        'sharp' => Icons.power_settings_new_sharp,
        _ => LucideIcons.power,
      };

  static IconData get public => switch (style) {
        'glass' => Icons.public_rounded,
        'sharp' => Icons.public_sharp,
        _ => LucideIcons.globe,
      };

  static IconData get queue_music => switch (style) {
        'glass' => Icons.queue_music_rounded,
        'sharp' => Icons.queue_music_sharp,
        _ => LucideIcons.listMusic,
      };

  static IconData get refresh => switch (style) {
        'glass' => Icons.refresh_rounded,
        'sharp' => Icons.refresh_sharp,
        _ => LucideIcons.refreshCw,
      };

  static IconData get refresh_rounded => switch (style) {
        'glass' => Icons.refresh_rounded,
        'sharp' => Icons.refresh_sharp,
        _ => LucideIcons.refreshCw,
      };

  static IconData get remove_circle_outline => switch (style) {
        'glass' => Icons.remove_circle_outline,
        'sharp' => Icons.remove_circle_outline,
        _ => LucideIcons.circleMinus,
      };

  static IconData get remove_rounded => switch (style) {
        'glass' => Icons.remove_rounded,
        'sharp' => Icons.remove_sharp,
        _ => LucideIcons.minus,
      };

  static IconData get repeat => switch (style) {
        'glass' => Icons.repeat_rounded,
        'sharp' => Icons.repeat_sharp,
        _ => LucideIcons.repeat,
      };

  static IconData get repeat_one => switch (style) {
        'glass' => Icons.repeat_one_rounded,
        'sharp' => Icons.repeat_one_sharp,
        _ => LucideIcons.repeat1,
      };

  static IconData get restart_alt => switch (style) {
        'glass' => Icons.restart_alt_rounded,
        'sharp' => Icons.restart_alt_sharp,
        _ => LucideIcons.rotateCcw,
      };

  static IconData get restart_alt_rounded => switch (style) {
        'glass' => Icons.restart_alt_rounded,
        'sharp' => Icons.restart_alt_sharp,
        _ => LucideIcons.rotateCcw,
      };

  static IconData get schedule => switch (style) {
        'glass' => Icons.schedule_rounded,
        'sharp' => Icons.schedule_sharp,
        _ => LucideIcons.clock,
      };

  static IconData get search => switch (style) {
        'glass' => Icons.search_rounded,
        'sharp' => Icons.search_sharp,
        _ => LucideIcons.search,
      };

  static IconData get search_off => switch (style) {
        'glass' => Icons.search_off_rounded,
        'sharp' => Icons.search_off_sharp,
        _ => LucideIcons.searchX,
      };

  static IconData get search_rounded => switch (style) {
        'glass' => Icons.search_rounded,
        'sharp' => Icons.search_sharp,
        _ => LucideIcons.search,
      };

  static IconData get select_all => switch (style) {
        'glass' => Icons.select_all_rounded,
        'sharp' => Icons.select_all_sharp,
        _ => LucideIcons.listChecks,
      };

  static IconData get settings_outlined => switch (style) {
        'glass' => Icons.settings_outlined,
        'sharp' => Icons.settings_outlined,
        _ => LucideIcons.settings,
      };

  static IconData get shield_outlined => switch (style) {
        'glass' => Icons.shield_outlined,
        'sharp' => Icons.shield_outlined,
        _ => LucideIcons.shield,
      };

  static IconData get shuffle => switch (style) {
        'glass' => Icons.shuffle_rounded,
        'sharp' => Icons.shuffle_sharp,
        _ => LucideIcons.shuffle,
      };

  static IconData get skip_next_rounded => switch (style) {
        'glass' => Icons.skip_next_rounded,
        'sharp' => Icons.skip_next_sharp,
        _ => Icons.skip_next_rounded,
      };

  static IconData get skip_previous_rounded => switch (style) {
        'glass' => Icons.skip_previous_rounded,
        'sharp' => Icons.skip_previous_sharp,
        _ => Icons.skip_previous_rounded,
      };

  static IconData get smart_display_outlined => switch (style) {
        'glass' => Icons.smart_display_outlined,
        'sharp' => Icons.smart_display_outlined,
        _ => Icons.smart_display_outlined,
      };

  static IconData get sort_by_alpha => switch (style) {
        'glass' => Icons.sort_by_alpha_rounded,
        'sharp' => Icons.sort_by_alpha_sharp,
        _ => LucideIcons.arrowDownAZ,
      };

  static IconData get storage_outlined => switch (style) {
        'glass' => Icons.storage_outlined,
        'sharp' => Icons.storage_outlined,
        _ => LucideIcons.hardDrive,
      };

  static IconData get swap_horiz_rounded => switch (style) {
        'glass' => Icons.swap_horiz_rounded,
        'sharp' => Icons.swap_horiz_sharp,
        _ => LucideIcons.arrowLeftRight,
      };

  static IconData get swap_vert => switch (style) {
        'glass' => Icons.swap_vert_rounded,
        'sharp' => Icons.swap_vert_sharp,
        _ => LucideIcons.arrowUpDown,
      };

  static IconData get system_update_alt => switch (style) {
        'glass' => Icons.system_update_alt_rounded,
        'sharp' => Icons.system_update_alt_sharp,
        _ => LucideIcons.download,
      };

  static IconData get table_chart_outlined => switch (style) {
        'glass' => Icons.table_chart_outlined,
        'sharp' => Icons.table_chart_outlined,
        _ => LucideIcons.table,
      };

  static IconData get thumb_down => switch (style) {
        'glass' => Icons.thumb_down_rounded,
        'sharp' => Icons.thumb_down_sharp,
        _ => Icons.thumb_down_rounded,
      };

  static IconData get thumb_down_alt_outlined => switch (style) {
        'glass' => Icons.thumb_down_alt_outlined,
        'sharp' => Icons.thumb_down_alt_outlined,
        _ => LucideIcons.thumbsDown,
      };

  static IconData get thumb_down_outlined => switch (style) {
        'glass' => Icons.thumb_down_outlined,
        'sharp' => Icons.thumb_down_outlined,
        _ => LucideIcons.thumbsDown,
      };

  static IconData get thumb_down_rounded => switch (style) {
        'glass' => Icons.thumb_down_rounded,
        'sharp' => Icons.thumb_down_sharp,
        _ => Icons.thumb_down_rounded,
      };

  static IconData get upload_file => switch (style) {
        'glass' => Icons.upload_file_rounded,
        'sharp' => Icons.upload_file_sharp,
        _ => LucideIcons.fileUp,
      };

  static IconData get verified_user_outlined => switch (style) {
        'glass' => Icons.verified_user_outlined,
        'sharp' => Icons.verified_user_outlined,
        _ => LucideIcons.shieldCheck,
      };

  static IconData get visibility => switch (style) {
        'glass' => Icons.visibility_rounded,
        'sharp' => Icons.visibility_sharp,
        _ => LucideIcons.eye,
      };

  static IconData get visibility_off_outlined => switch (style) {
        'glass' => Icons.visibility_off_outlined,
        'sharp' => Icons.visibility_off_outlined,
        _ => LucideIcons.eyeOff,
      };

  static IconData get visibility_outlined => switch (style) {
        'glass' => Icons.visibility_outlined,
        'sharp' => Icons.visibility_outlined,
        _ => LucideIcons.eye,
      };

  static IconData get volume_down => switch (style) {
        'glass' => Icons.volume_down_rounded,
        'sharp' => Icons.volume_down_sharp,
        _ => LucideIcons.volume1,
      };

  static IconData get volume_down_rounded => switch (style) {
        'glass' => Icons.volume_down_rounded,
        'sharp' => Icons.volume_down_sharp,
        _ => LucideIcons.volume1,
      };

  static IconData get volume_off => switch (style) {
        'glass' => Icons.volume_off_rounded,
        'sharp' => Icons.volume_off_sharp,
        _ => LucideIcons.volumeX,
      };

  static IconData get volume_up => switch (style) {
        'glass' => Icons.volume_up_rounded,
        'sharp' => Icons.volume_up_sharp,
        _ => LucideIcons.volume2,
      };

  static IconData get vpn_lock_outlined => switch (style) {
        'glass' => Icons.vpn_lock_outlined,
        'sharp' => Icons.vpn_lock_outlined,
        _ => LucideIcons.shieldCheck,
      };

  static IconData get wallpaper_outlined => switch (style) {
        'glass' => Icons.wallpaper_outlined,
        'sharp' => Icons.wallpaper_outlined,
        _ => LucideIcons.image,
      };

  static IconData get waves => switch (style) {
        'glass' => Icons.waves_rounded,
        'sharp' => Icons.waves_sharp,
        _ => LucideIcons.audioWaveform,
      };
}
