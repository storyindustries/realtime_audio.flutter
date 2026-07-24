// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'realtime_audio_echo_cancellation_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$RealtimeAudioEchoCancellationState {

/// Whether voice processing / AEC was requested for this engine.
 bool get requested;/// Whether the platform confirmed (by read-back) that AEC is enabled.
 bool get nativeEnabled;/// Which mechanism the engine is driving. Unknown values decode to
/// [RealtimeAudioEchoCancellationMechanism.none].
@JsonKey(unknownEnumValue: RealtimeAudioEchoCancellationMechanism.none) RealtimeAudioEchoCancellationMechanism get mechanism;/// Whether the mic capture path has delivered its first real buffer.
 bool get captureProvenLive;/// The software APM's measured echo-return-loss-enhancement (dB), when it
/// reports one. Null on the platform mechanism, on AECM, and before the
/// canceller has converged.
 double? get erleDb;/// `aec3` | `aecm` while the software APM runs; null otherwise.
 String? get apmMode;
/// Create a copy of RealtimeAudioEchoCancellationState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RealtimeAudioEchoCancellationStateCopyWith<RealtimeAudioEchoCancellationState> get copyWith => _$RealtimeAudioEchoCancellationStateCopyWithImpl<RealtimeAudioEchoCancellationState>(this as RealtimeAudioEchoCancellationState, _$identity);

  /// Serializes this RealtimeAudioEchoCancellationState to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RealtimeAudioEchoCancellationState&&(identical(other.requested, requested) || other.requested == requested)&&(identical(other.nativeEnabled, nativeEnabled) || other.nativeEnabled == nativeEnabled)&&(identical(other.mechanism, mechanism) || other.mechanism == mechanism)&&(identical(other.captureProvenLive, captureProvenLive) || other.captureProvenLive == captureProvenLive)&&(identical(other.erleDb, erleDb) || other.erleDb == erleDb)&&(identical(other.apmMode, apmMode) || other.apmMode == apmMode));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,requested,nativeEnabled,mechanism,captureProvenLive,erleDb,apmMode);

@override
String toString() {
  return 'RealtimeAudioEchoCancellationState(requested: $requested, nativeEnabled: $nativeEnabled, mechanism: $mechanism, captureProvenLive: $captureProvenLive, erleDb: $erleDb, apmMode: $apmMode)';
}


}

/// @nodoc
abstract mixin class $RealtimeAudioEchoCancellationStateCopyWith<$Res>  {
  factory $RealtimeAudioEchoCancellationStateCopyWith(RealtimeAudioEchoCancellationState value, $Res Function(RealtimeAudioEchoCancellationState) _then) = _$RealtimeAudioEchoCancellationStateCopyWithImpl;
@useResult
$Res call({
 bool requested, bool nativeEnabled,@JsonKey(unknownEnumValue: RealtimeAudioEchoCancellationMechanism.none) RealtimeAudioEchoCancellationMechanism mechanism, bool captureProvenLive, double? erleDb, String? apmMode
});




}
/// @nodoc
class _$RealtimeAudioEchoCancellationStateCopyWithImpl<$Res>
    implements $RealtimeAudioEchoCancellationStateCopyWith<$Res> {
  _$RealtimeAudioEchoCancellationStateCopyWithImpl(this._self, this._then);

  final RealtimeAudioEchoCancellationState _self;
  final $Res Function(RealtimeAudioEchoCancellationState) _then;

/// Create a copy of RealtimeAudioEchoCancellationState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? requested = null,Object? nativeEnabled = null,Object? mechanism = null,Object? captureProvenLive = null,Object? erleDb = freezed,Object? apmMode = freezed,}) {
  return _then(_self.copyWith(
requested: null == requested ? _self.requested : requested // ignore: cast_nullable_to_non_nullable
as bool,nativeEnabled: null == nativeEnabled ? _self.nativeEnabled : nativeEnabled // ignore: cast_nullable_to_non_nullable
as bool,mechanism: null == mechanism ? _self.mechanism : mechanism // ignore: cast_nullable_to_non_nullable
as RealtimeAudioEchoCancellationMechanism,captureProvenLive: null == captureProvenLive ? _self.captureProvenLive : captureProvenLive // ignore: cast_nullable_to_non_nullable
as bool,erleDb: freezed == erleDb ? _self.erleDb : erleDb // ignore: cast_nullable_to_non_nullable
as double?,apmMode: freezed == apmMode ? _self.apmMode : apmMode // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [RealtimeAudioEchoCancellationState].
extension RealtimeAudioEchoCancellationStatePatterns on RealtimeAudioEchoCancellationState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RealtimeAudioEchoCancellationState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RealtimeAudioEchoCancellationState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RealtimeAudioEchoCancellationState value)  $default,){
final _that = this;
switch (_that) {
case _RealtimeAudioEchoCancellationState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RealtimeAudioEchoCancellationState value)?  $default,){
final _that = this;
switch (_that) {
case _RealtimeAudioEchoCancellationState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool requested,  bool nativeEnabled, @JsonKey(unknownEnumValue: RealtimeAudioEchoCancellationMechanism.none)  RealtimeAudioEchoCancellationMechanism mechanism,  bool captureProvenLive,  double? erleDb,  String? apmMode)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RealtimeAudioEchoCancellationState() when $default != null:
return $default(_that.requested,_that.nativeEnabled,_that.mechanism,_that.captureProvenLive,_that.erleDb,_that.apmMode);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool requested,  bool nativeEnabled, @JsonKey(unknownEnumValue: RealtimeAudioEchoCancellationMechanism.none)  RealtimeAudioEchoCancellationMechanism mechanism,  bool captureProvenLive,  double? erleDb,  String? apmMode)  $default,) {final _that = this;
switch (_that) {
case _RealtimeAudioEchoCancellationState():
return $default(_that.requested,_that.nativeEnabled,_that.mechanism,_that.captureProvenLive,_that.erleDb,_that.apmMode);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool requested,  bool nativeEnabled, @JsonKey(unknownEnumValue: RealtimeAudioEchoCancellationMechanism.none)  RealtimeAudioEchoCancellationMechanism mechanism,  bool captureProvenLive,  double? erleDb,  String? apmMode)?  $default,) {final _that = this;
switch (_that) {
case _RealtimeAudioEchoCancellationState() when $default != null:
return $default(_that.requested,_that.nativeEnabled,_that.mechanism,_that.captureProvenLive,_that.erleDb,_that.apmMode);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RealtimeAudioEchoCancellationState extends RealtimeAudioEchoCancellationState {
  const _RealtimeAudioEchoCancellationState({this.requested = false, this.nativeEnabled = false, @JsonKey(unknownEnumValue: RealtimeAudioEchoCancellationMechanism.none) this.mechanism = RealtimeAudioEchoCancellationMechanism.none, this.captureProvenLive = false, this.erleDb, this.apmMode}): super._();
  factory _RealtimeAudioEchoCancellationState.fromJson(Map<String, dynamic> json) => _$RealtimeAudioEchoCancellationStateFromJson(json);

/// Whether voice processing / AEC was requested for this engine.
@override@JsonKey() final  bool requested;
/// Whether the platform confirmed (by read-back) that AEC is enabled.
@override@JsonKey() final  bool nativeEnabled;
/// Which mechanism the engine is driving. Unknown values decode to
/// [RealtimeAudioEchoCancellationMechanism.none].
@override@JsonKey(unknownEnumValue: RealtimeAudioEchoCancellationMechanism.none) final  RealtimeAudioEchoCancellationMechanism mechanism;
/// Whether the mic capture path has delivered its first real buffer.
@override@JsonKey() final  bool captureProvenLive;
/// The software APM's measured echo-return-loss-enhancement (dB), when it
/// reports one. Null on the platform mechanism, on AECM, and before the
/// canceller has converged.
@override final  double? erleDb;
/// `aec3` | `aecm` while the software APM runs; null otherwise.
@override final  String? apmMode;

/// Create a copy of RealtimeAudioEchoCancellationState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RealtimeAudioEchoCancellationStateCopyWith<_RealtimeAudioEchoCancellationState> get copyWith => __$RealtimeAudioEchoCancellationStateCopyWithImpl<_RealtimeAudioEchoCancellationState>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RealtimeAudioEchoCancellationStateToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RealtimeAudioEchoCancellationState&&(identical(other.requested, requested) || other.requested == requested)&&(identical(other.nativeEnabled, nativeEnabled) || other.nativeEnabled == nativeEnabled)&&(identical(other.mechanism, mechanism) || other.mechanism == mechanism)&&(identical(other.captureProvenLive, captureProvenLive) || other.captureProvenLive == captureProvenLive)&&(identical(other.erleDb, erleDb) || other.erleDb == erleDb)&&(identical(other.apmMode, apmMode) || other.apmMode == apmMode));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,requested,nativeEnabled,mechanism,captureProvenLive,erleDb,apmMode);

@override
String toString() {
  return 'RealtimeAudioEchoCancellationState(requested: $requested, nativeEnabled: $nativeEnabled, mechanism: $mechanism, captureProvenLive: $captureProvenLive, erleDb: $erleDb, apmMode: $apmMode)';
}


}

/// @nodoc
abstract mixin class _$RealtimeAudioEchoCancellationStateCopyWith<$Res> implements $RealtimeAudioEchoCancellationStateCopyWith<$Res> {
  factory _$RealtimeAudioEchoCancellationStateCopyWith(_RealtimeAudioEchoCancellationState value, $Res Function(_RealtimeAudioEchoCancellationState) _then) = __$RealtimeAudioEchoCancellationStateCopyWithImpl;
@override @useResult
$Res call({
 bool requested, bool nativeEnabled,@JsonKey(unknownEnumValue: RealtimeAudioEchoCancellationMechanism.none) RealtimeAudioEchoCancellationMechanism mechanism, bool captureProvenLive, double? erleDb, String? apmMode
});




}
/// @nodoc
class __$RealtimeAudioEchoCancellationStateCopyWithImpl<$Res>
    implements _$RealtimeAudioEchoCancellationStateCopyWith<$Res> {
  __$RealtimeAudioEchoCancellationStateCopyWithImpl(this._self, this._then);

  final _RealtimeAudioEchoCancellationState _self;
  final $Res Function(_RealtimeAudioEchoCancellationState) _then;

/// Create a copy of RealtimeAudioEchoCancellationState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? requested = null,Object? nativeEnabled = null,Object? mechanism = null,Object? captureProvenLive = null,Object? erleDb = freezed,Object? apmMode = freezed,}) {
  return _then(_RealtimeAudioEchoCancellationState(
requested: null == requested ? _self.requested : requested // ignore: cast_nullable_to_non_nullable
as bool,nativeEnabled: null == nativeEnabled ? _self.nativeEnabled : nativeEnabled // ignore: cast_nullable_to_non_nullable
as bool,mechanism: null == mechanism ? _self.mechanism : mechanism // ignore: cast_nullable_to_non_nullable
as RealtimeAudioEchoCancellationMechanism,captureProvenLive: null == captureProvenLive ? _self.captureProvenLive : captureProvenLive // ignore: cast_nullable_to_non_nullable
as bool,erleDb: freezed == erleDb ? _self.erleDb : erleDb // ignore: cast_nullable_to_non_nullable
as double?,apmMode: freezed == apmMode ? _self.apmMode : apmMode // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
