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

/// Milliseconds of the current/last stream the device actually rendered.
 int get renderedMs;/// Whether the device is actively rendering queued PCM ahead of the head
/// right now (false when paused, stalled, drained, or stopped).
 bool get isRendering;/// Total queued milliseconds of the current stream (rendered + pending).
 int get durationTotalMs;
/// Create a copy of RealtimeAudioPlaybackClock
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RealtimeAudioPlaybackClockCopyWith<RealtimeAudioPlaybackClock> get copyWith => _$RealtimeAudioPlaybackClockCopyWithImpl<RealtimeAudioPlaybackClock>(this as RealtimeAudioPlaybackClock, _$identity);

  /// Serializes this RealtimeAudioPlaybackClock to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RealtimeAudioPlaybackClock&&(identical(other.renderedMs, renderedMs) || other.renderedMs == renderedMs)&&(identical(other.isRendering, isRendering) || other.isRendering == isRendering)&&(identical(other.durationTotalMs, durationTotalMs) || other.durationTotalMs == durationTotalMs));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,renderedMs,isRendering,durationTotalMs);

@override
String toString() {
  return 'RealtimeAudioPlaybackClock(renderedMs: $renderedMs, isRendering: $isRendering, durationTotalMs: $durationTotalMs)';
}


}

/// @nodoc
abstract mixin class $RealtimeAudioPlaybackClockCopyWith<$Res>  {
  factory $RealtimeAudioPlaybackClockCopyWith(RealtimeAudioPlaybackClock value, $Res Function(RealtimeAudioPlaybackClock) _then) = _$RealtimeAudioPlaybackClockCopyWithImpl;
@useResult
$Res call({
 int renderedMs, bool isRendering, int durationTotalMs
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
@pragma('vm:prefer-inline') @override $Res call({Object? renderedMs = null,Object? isRendering = null,Object? durationTotalMs = null,}) {
  return _then(_self.copyWith(
renderedMs: null == renderedMs ? _self.renderedMs : renderedMs // ignore: cast_nullable_to_non_nullable
as int,isRendering: null == isRendering ? _self.isRendering : isRendering // ignore: cast_nullable_to_non_nullable
as bool,durationTotalMs: null == durationTotalMs ? _self.durationTotalMs : durationTotalMs // ignore: cast_nullable_to_non_nullable
as int,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int renderedMs,  bool isRendering,  int durationTotalMs)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RealtimeAudioPlaybackClock() when $default != null:
return $default(_that.renderedMs,_that.isRendering,_that.durationTotalMs);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int renderedMs,  bool isRendering,  int durationTotalMs)  $default,) {final _that = this;
switch (_that) {
case _RealtimeAudioPlaybackClock():
return $default(_that.renderedMs,_that.isRendering,_that.durationTotalMs);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int renderedMs,  bool isRendering,  int durationTotalMs)?  $default,) {final _that = this;
switch (_that) {
case _RealtimeAudioPlaybackClock() when $default != null:
return $default(_that.renderedMs,_that.isRendering,_that.durationTotalMs);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RealtimeAudioPlaybackClock extends RealtimeAudioPlaybackClock {
  const _RealtimeAudioPlaybackClock({this.renderedMs = 0, this.isRendering = false, this.durationTotalMs = 0}): super._();
  factory _RealtimeAudioPlaybackClock.fromJson(Map<String, dynamic> json) => _$RealtimeAudioPlaybackClockFromJson(json);

/// Milliseconds of the current/last stream the device actually rendered.
@override@JsonKey() final  int renderedMs;
/// Whether the device is actively rendering queued PCM ahead of the head
/// right now (false when paused, stalled, drained, or stopped).
@override@JsonKey() final  bool isRendering;
/// Total queued milliseconds of the current stream (rendered + pending).
@override@JsonKey() final  int durationTotalMs;

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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RealtimeAudioPlaybackClock&&(identical(other.renderedMs, renderedMs) || other.renderedMs == renderedMs)&&(identical(other.isRendering, isRendering) || other.isRendering == isRendering)&&(identical(other.durationTotalMs, durationTotalMs) || other.durationTotalMs == durationTotalMs));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,renderedMs,isRendering,durationTotalMs);

@override
String toString() {
  return 'RealtimeAudioPlaybackClock(renderedMs: $renderedMs, isRendering: $isRendering, durationTotalMs: $durationTotalMs)';
}


}

/// @nodoc
abstract mixin class _$RealtimeAudioPlaybackClockCopyWith<$Res> implements $RealtimeAudioPlaybackClockCopyWith<$Res> {
  factory _$RealtimeAudioPlaybackClockCopyWith(_RealtimeAudioPlaybackClock value, $Res Function(_RealtimeAudioPlaybackClock) _then) = __$RealtimeAudioPlaybackClockCopyWithImpl;
@override @useResult
$Res call({
 int renderedMs, bool isRendering, int durationTotalMs
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
@override @pragma('vm:prefer-inline') $Res call({Object? renderedMs = null,Object? isRendering = null,Object? durationTotalMs = null,}) {
  return _then(_RealtimeAudioPlaybackClock(
renderedMs: null == renderedMs ? _self.renderedMs : renderedMs // ignore: cast_nullable_to_non_nullable
as int,isRendering: null == isRendering ? _self.isRendering : isRendering // ignore: cast_nullable_to_non_nullable
as bool,durationTotalMs: null == durationTotalMs ? _self.durationTotalMs : durationTotalMs // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
