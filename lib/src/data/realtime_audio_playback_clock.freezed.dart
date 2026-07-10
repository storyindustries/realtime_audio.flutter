// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'realtime_audio_playback_clock.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$RealtimeAudioPlaybackClock {

/// Completion-INDEPENDENT render clock (ms): the platform playback-head
/// timeline (iOS `AVAudioPlayerNode.playerTime`, Android
/// `AudioTrack.playbackHeadPosition`), folded across stops. Keeps advancing
/// even when per-buffer completion callbacks stall or die — this is the
/// device-truth "how much actually played out" signal.
 int get renderClockMs;/// Completion-DRIVEN rendered ms: accumulated only from real playout
/// completions (iOS `.dataPlayedBack`; flushed buffers never count). On
/// Android — which has no per-buffer playout callback — this mirrors
/// [renderClockMs].
 int get renderedMs;/// Total ms ever scheduled onto the player (monotonic upper bound).
 int get scheduledMs;/// Whether the device is actively rendering right now: buffers outstanding
/// (or within the post-drain hangover), and not paused.
 bool get isRendering;
/// Create a copy of RealtimeAudioPlaybackClock
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RealtimeAudioPlaybackClockCopyWith<RealtimeAudioPlaybackClock> get copyWith => _$RealtimeAudioPlaybackClockCopyWithImpl<RealtimeAudioPlaybackClock>(this as RealtimeAudioPlaybackClock, _$identity);

  /// Serializes this RealtimeAudioPlaybackClock to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RealtimeAudioPlaybackClock&&(identical(other.renderClockMs, renderClockMs) || other.renderClockMs == renderClockMs)&&(identical(other.renderedMs, renderedMs) || other.renderedMs == renderedMs)&&(identical(other.scheduledMs, scheduledMs) || other.scheduledMs == scheduledMs)&&(identical(other.isRendering, isRendering) || other.isRendering == isRendering));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,renderClockMs,renderedMs,scheduledMs,isRendering);

@override
String toString() {
  return 'RealtimeAudioPlaybackClock(renderClockMs: $renderClockMs, renderedMs: $renderedMs, scheduledMs: $scheduledMs, isRendering: $isRendering)';
}


}

/// @nodoc
abstract mixin class $RealtimeAudioPlaybackClockCopyWith<$Res>  {
  factory $RealtimeAudioPlaybackClockCopyWith(RealtimeAudioPlaybackClock value, $Res Function(RealtimeAudioPlaybackClock) _then) = _$RealtimeAudioPlaybackClockCopyWithImpl;
@useResult
$Res call({
 int renderClockMs, int renderedMs, int scheduledMs, bool isRendering
});




}
/// @nodoc
class _$RealtimeAudioPlaybackClockCopyWithImpl<$Res>
    implements $RealtimeAudioPlaybackClockCopyWith<$Res> {
  _$RealtimeAudioPlaybackClockCopyWithImpl(this._self, this._then);

  final RealtimeAudioPlaybackClock _self;
  final $Res Function(RealtimeAudioPlaybackClock) _then;

/// Create a copy of RealtimeAudioPlaybackClock
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? renderClockMs = null,Object? renderedMs = null,Object? scheduledMs = null,Object? isRendering = null,}) {
  return _then(_self.copyWith(
renderClockMs: null == renderClockMs ? _self.renderClockMs : renderClockMs // ignore: cast_nullable_to_non_nullable
as int,renderedMs: null == renderedMs ? _self.renderedMs : renderedMs // ignore: cast_nullable_to_non_nullable
as int,scheduledMs: null == scheduledMs ? _self.scheduledMs : scheduledMs // ignore: cast_nullable_to_non_nullable
as int,isRendering: null == isRendering ? _self.isRendering : isRendering // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [RealtimeAudioPlaybackClock].
extension RealtimeAudioPlaybackClockPatterns on RealtimeAudioPlaybackClock {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RealtimeAudioPlaybackClock value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RealtimeAudioPlaybackClock() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RealtimeAudioPlaybackClock value)  $default,){
final _that = this;
switch (_that) {
case _RealtimeAudioPlaybackClock():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RealtimeAudioPlaybackClock value)?  $default,){
final _that = this;
switch (_that) {
case _RealtimeAudioPlaybackClock() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int renderClockMs,  int renderedMs,  int scheduledMs,  bool isRendering)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RealtimeAudioPlaybackClock() when $default != null:
return $default(_that.renderClockMs,_that.renderedMs,_that.scheduledMs,_that.isRendering);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int renderClockMs,  int renderedMs,  int scheduledMs,  bool isRendering)  $default,) {final _that = this;
switch (_that) {
case _RealtimeAudioPlaybackClock():
return $default(_that.renderClockMs,_that.renderedMs,_that.scheduledMs,_that.isRendering);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int renderClockMs,  int renderedMs,  int scheduledMs,  bool isRendering)?  $default,) {final _that = this;
switch (_that) {
case _RealtimeAudioPlaybackClock() when $default != null:
return $default(_that.renderClockMs,_that.renderedMs,_that.scheduledMs,_that.isRendering);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RealtimeAudioPlaybackClock extends RealtimeAudioPlaybackClock {
  const _RealtimeAudioPlaybackClock({this.renderClockMs = 0, this.renderedMs = 0, this.scheduledMs = 0, this.isRendering = false}): super._();
  factory _RealtimeAudioPlaybackClock.fromJson(Map<String, dynamic> json) => _$RealtimeAudioPlaybackClockFromJson(json);

/// Completion-INDEPENDENT render clock (ms): the platform playback-head
/// timeline (iOS `AVAudioPlayerNode.playerTime`, Android
/// `AudioTrack.playbackHeadPosition`), folded across stops. Keeps advancing
/// even when per-buffer completion callbacks stall or die — this is the
/// device-truth "how much actually played out" signal.
@override@JsonKey() final  int renderClockMs;
/// Completion-DRIVEN rendered ms: accumulated only from real playout
/// completions (iOS `.dataPlayedBack`; flushed buffers never count). On
/// Android — which has no per-buffer playout callback — this mirrors
/// [renderClockMs].
@override@JsonKey() final  int renderedMs;
/// Total ms ever scheduled onto the player (monotonic upper bound).
@override@JsonKey() final  int scheduledMs;
/// Whether the device is actively rendering right now: buffers outstanding
/// (or within the post-drain hangover), and not paused.
@override@JsonKey() final  bool isRendering;

/// Create a copy of RealtimeAudioPlaybackClock
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RealtimeAudioPlaybackClockCopyWith<_RealtimeAudioPlaybackClock> get copyWith => __$RealtimeAudioPlaybackClockCopyWithImpl<_RealtimeAudioPlaybackClock>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RealtimeAudioPlaybackClockToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RealtimeAudioPlaybackClock&&(identical(other.renderClockMs, renderClockMs) || other.renderClockMs == renderClockMs)&&(identical(other.renderedMs, renderedMs) || other.renderedMs == renderedMs)&&(identical(other.scheduledMs, scheduledMs) || other.scheduledMs == scheduledMs)&&(identical(other.isRendering, isRendering) || other.isRendering == isRendering));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,renderClockMs,renderedMs,scheduledMs,isRendering);

@override
String toString() {
  return 'RealtimeAudioPlaybackClock(renderClockMs: $renderClockMs, renderedMs: $renderedMs, scheduledMs: $scheduledMs, isRendering: $isRendering)';
}


}

/// @nodoc
abstract mixin class _$RealtimeAudioPlaybackClockCopyWith<$Res> implements $RealtimeAudioPlaybackClockCopyWith<$Res> {
  factory _$RealtimeAudioPlaybackClockCopyWith(_RealtimeAudioPlaybackClock value, $Res Function(_RealtimeAudioPlaybackClock) _then) = __$RealtimeAudioPlaybackClockCopyWithImpl;
@override @useResult
$Res call({
 int renderClockMs, int renderedMs, int scheduledMs, bool isRendering
});




}
/// @nodoc
class __$RealtimeAudioPlaybackClockCopyWithImpl<$Res>
    implements _$RealtimeAudioPlaybackClockCopyWith<$Res> {
  __$RealtimeAudioPlaybackClockCopyWithImpl(this._self, this._then);

  final _RealtimeAudioPlaybackClock _self;
  final $Res Function(_RealtimeAudioPlaybackClock) _then;

/// Create a copy of RealtimeAudioPlaybackClock
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? renderClockMs = null,Object? renderedMs = null,Object? scheduledMs = null,Object? isRendering = null,}) {
  return _then(_RealtimeAudioPlaybackClock(
renderClockMs: null == renderClockMs ? _self.renderClockMs : renderClockMs // ignore: cast_nullable_to_non_nullable
as int,renderedMs: null == renderedMs ? _self.renderedMs : renderedMs // ignore: cast_nullable_to_non_nullable
as int,scheduledMs: null == scheduledMs ? _self.scheduledMs : scheduledMs // ignore: cast_nullable_to_non_nullable
as int,isRendering: null == isRendering ? _self.isRendering : isRendering // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
