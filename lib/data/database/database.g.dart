// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ProjectsTable extends Projects
    with TableInfo<$ProjectsTable, ProjectRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetUrlMeta = const VerificationMeta(
    'targetUrl',
  );
  @override
  late final GeneratedColumn<String> targetUrl = GeneratedColumn<String>(
    'target_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _allowPrivateNetworkMeta =
      const VerificationMeta('allowPrivateNetwork');
  @override
  late final GeneratedColumn<bool> allowPrivateNetwork = GeneratedColumn<bool>(
    'allow_private_network',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("allow_private_network" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _defaultLayoutModeMeta = const VerificationMeta(
    'defaultLayoutMode',
  );
  @override
  late final GeneratedColumn<String> defaultLayoutMode =
      GeneratedColumn<String>(
        'default_layout_mode',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('grid'),
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    targetUrl,
    allowPrivateNetwork,
    createdAt,
    updatedAt,
    defaultLayoutMode,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'projects';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProjectRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('target_url')) {
      context.handle(
        _targetUrlMeta,
        targetUrl.isAcceptableOrUnknown(data['target_url']!, _targetUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_targetUrlMeta);
    }
    if (data.containsKey('allow_private_network')) {
      context.handle(
        _allowPrivateNetworkMeta,
        allowPrivateNetwork.isAcceptableOrUnknown(
          data['allow_private_network']!,
          _allowPrivateNetworkMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('default_layout_mode')) {
      context.handle(
        _defaultLayoutModeMeta,
        defaultLayoutMode.isAcceptableOrUnknown(
          data['default_layout_mode']!,
          _defaultLayoutModeMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProjectRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProjectRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      targetUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_url'],
      )!,
      allowPrivateNetwork: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}allow_private_network'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      defaultLayoutMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}default_layout_mode'],
      )!,
    );
  }

  @override
  $ProjectsTable createAlias(String alias) {
    return $ProjectsTable(attachedDatabase, alias);
  }
}

class ProjectRow extends DataClass implements Insertable<ProjectRow> {
  final String id;
  final String name;
  final String targetUrl;
  final bool allowPrivateNetwork;
  final int createdAt;
  final int updatedAt;
  final String defaultLayoutMode;
  const ProjectRow({
    required this.id,
    required this.name,
    required this.targetUrl,
    required this.allowPrivateNetwork,
    required this.createdAt,
    required this.updatedAt,
    required this.defaultLayoutMode,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['target_url'] = Variable<String>(targetUrl);
    map['allow_private_network'] = Variable<bool>(allowPrivateNetwork);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    map['default_layout_mode'] = Variable<String>(defaultLayoutMode);
    return map;
  }

  ProjectsCompanion toCompanion(bool nullToAbsent) {
    return ProjectsCompanion(
      id: Value(id),
      name: Value(name),
      targetUrl: Value(targetUrl),
      allowPrivateNetwork: Value(allowPrivateNetwork),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      defaultLayoutMode: Value(defaultLayoutMode),
    );
  }

  factory ProjectRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProjectRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      targetUrl: serializer.fromJson<String>(json['targetUrl']),
      allowPrivateNetwork: serializer.fromJson<bool>(
        json['allowPrivateNetwork'],
      ),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      defaultLayoutMode: serializer.fromJson<String>(json['defaultLayoutMode']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'targetUrl': serializer.toJson<String>(targetUrl),
      'allowPrivateNetwork': serializer.toJson<bool>(allowPrivateNetwork),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'defaultLayoutMode': serializer.toJson<String>(defaultLayoutMode),
    };
  }

  ProjectRow copyWith({
    String? id,
    String? name,
    String? targetUrl,
    bool? allowPrivateNetwork,
    int? createdAt,
    int? updatedAt,
    String? defaultLayoutMode,
  }) => ProjectRow(
    id: id ?? this.id,
    name: name ?? this.name,
    targetUrl: targetUrl ?? this.targetUrl,
    allowPrivateNetwork: allowPrivateNetwork ?? this.allowPrivateNetwork,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    defaultLayoutMode: defaultLayoutMode ?? this.defaultLayoutMode,
  );
  ProjectRow copyWithCompanion(ProjectsCompanion data) {
    return ProjectRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      targetUrl: data.targetUrl.present ? data.targetUrl.value : this.targetUrl,
      allowPrivateNetwork: data.allowPrivateNetwork.present
          ? data.allowPrivateNetwork.value
          : this.allowPrivateNetwork,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      defaultLayoutMode: data.defaultLayoutMode.present
          ? data.defaultLayoutMode.value
          : this.defaultLayoutMode,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProjectRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('targetUrl: $targetUrl, ')
          ..write('allowPrivateNetwork: $allowPrivateNetwork, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('defaultLayoutMode: $defaultLayoutMode')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    targetUrl,
    allowPrivateNetwork,
    createdAt,
    updatedAt,
    defaultLayoutMode,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProjectRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.targetUrl == this.targetUrl &&
          other.allowPrivateNetwork == this.allowPrivateNetwork &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.defaultLayoutMode == this.defaultLayoutMode);
}

class ProjectsCompanion extends UpdateCompanion<ProjectRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> targetUrl;
  final Value<bool> allowPrivateNetwork;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<String> defaultLayoutMode;
  final Value<int> rowid;
  const ProjectsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.targetUrl = const Value.absent(),
    this.allowPrivateNetwork = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.defaultLayoutMode = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProjectsCompanion.insert({
    required String id,
    required String name,
    required String targetUrl,
    this.allowPrivateNetwork = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.defaultLayoutMode = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       targetUrl = Value(targetUrl),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ProjectRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? targetUrl,
    Expression<bool>? allowPrivateNetwork,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<String>? defaultLayoutMode,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (targetUrl != null) 'target_url': targetUrl,
      if (allowPrivateNetwork != null)
        'allow_private_network': allowPrivateNetwork,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (defaultLayoutMode != null) 'default_layout_mode': defaultLayoutMode,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProjectsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? targetUrl,
    Value<bool>? allowPrivateNetwork,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<String>? defaultLayoutMode,
    Value<int>? rowid,
  }) {
    return ProjectsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      targetUrl: targetUrl ?? this.targetUrl,
      allowPrivateNetwork: allowPrivateNetwork ?? this.allowPrivateNetwork,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      defaultLayoutMode: defaultLayoutMode ?? this.defaultLayoutMode,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (targetUrl.present) {
      map['target_url'] = Variable<String>(targetUrl.value);
    }
    if (allowPrivateNetwork.present) {
      map['allow_private_network'] = Variable<bool>(allowPrivateNetwork.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (defaultLayoutMode.present) {
      map['default_layout_mode'] = Variable<String>(defaultLayoutMode.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProjectsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('targetUrl: $targetUrl, ')
          ..write('allowPrivateNetwork: $allowPrivateNetwork, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('defaultLayoutMode: $defaultLayoutMode, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $IdentitiesTable extends Identities
    with TableInfo<$IdentitiesTable, IdentityRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $IdentitiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES projects (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isolationModeMeta = const VerificationMeta(
    'isolationMode',
  );
  @override
  late final GeneratedColumn<String> isolationMode = GeneratedColumn<String>(
    'isolation_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _devicePresetIdMeta = const VerificationMeta(
    'devicePresetId',
  );
  @override
  late final GeneratedColumn<String> devicePresetId = GeneratedColumn<String>(
    'device_preset_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startPathMeta = const VerificationMeta(
    'startPath',
  );
  @override
  late final GeneratedColumn<String> startPath = GeneratedColumn<String>(
    'start_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('/'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    projectId,
    name,
    color,
    isolationMode,
    devicePresetId,
    startPath,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'identities';
  @override
  VerificationContext validateIntegrity(
    Insertable<IdentityRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_projectIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    } else if (isInserting) {
      context.missing(_colorMeta);
    }
    if (data.containsKey('isolation_mode')) {
      context.handle(
        _isolationModeMeta,
        isolationMode.isAcceptableOrUnknown(
          data['isolation_mode']!,
          _isolationModeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_isolationModeMeta);
    }
    if (data.containsKey('device_preset_id')) {
      context.handle(
        _devicePresetIdMeta,
        devicePresetId.isAcceptableOrUnknown(
          data['device_preset_id']!,
          _devicePresetIdMeta,
        ),
      );
    }
    if (data.containsKey('start_path')) {
      context.handle(
        _startPathMeta,
        startPath.isAcceptableOrUnknown(data['start_path']!, _startPathMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {projectId, name},
  ];
  @override
  IdentityRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return IdentityRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      )!,
      isolationMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}isolation_mode'],
      )!,
      devicePresetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_preset_id'],
      ),
      startPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}start_path'],
      )!,
    );
  }

  @override
  $IdentitiesTable createAlias(String alias) {
    return $IdentitiesTable(attachedDatabase, alias);
  }
}

class IdentityRow extends DataClass implements Insertable<IdentityRow> {
  final String id;
  final String projectId;
  final String name;
  final String color;
  final String isolationMode;
  final String? devicePresetId;
  final String startPath;
  const IdentityRow({
    required this.id,
    required this.projectId,
    required this.name,
    required this.color,
    required this.isolationMode,
    this.devicePresetId,
    required this.startPath,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['project_id'] = Variable<String>(projectId);
    map['name'] = Variable<String>(name);
    map['color'] = Variable<String>(color);
    map['isolation_mode'] = Variable<String>(isolationMode);
    if (!nullToAbsent || devicePresetId != null) {
      map['device_preset_id'] = Variable<String>(devicePresetId);
    }
    map['start_path'] = Variable<String>(startPath);
    return map;
  }

  IdentitiesCompanion toCompanion(bool nullToAbsent) {
    return IdentitiesCompanion(
      id: Value(id),
      projectId: Value(projectId),
      name: Value(name),
      color: Value(color),
      isolationMode: Value(isolationMode),
      devicePresetId: devicePresetId == null && nullToAbsent
          ? const Value.absent()
          : Value(devicePresetId),
      startPath: Value(startPath),
    );
  }

  factory IdentityRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return IdentityRow(
      id: serializer.fromJson<String>(json['id']),
      projectId: serializer.fromJson<String>(json['projectId']),
      name: serializer.fromJson<String>(json['name']),
      color: serializer.fromJson<String>(json['color']),
      isolationMode: serializer.fromJson<String>(json['isolationMode']),
      devicePresetId: serializer.fromJson<String?>(json['devicePresetId']),
      startPath: serializer.fromJson<String>(json['startPath']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'projectId': serializer.toJson<String>(projectId),
      'name': serializer.toJson<String>(name),
      'color': serializer.toJson<String>(color),
      'isolationMode': serializer.toJson<String>(isolationMode),
      'devicePresetId': serializer.toJson<String?>(devicePresetId),
      'startPath': serializer.toJson<String>(startPath),
    };
  }

  IdentityRow copyWith({
    String? id,
    String? projectId,
    String? name,
    String? color,
    String? isolationMode,
    Value<String?> devicePresetId = const Value.absent(),
    String? startPath,
  }) => IdentityRow(
    id: id ?? this.id,
    projectId: projectId ?? this.projectId,
    name: name ?? this.name,
    color: color ?? this.color,
    isolationMode: isolationMode ?? this.isolationMode,
    devicePresetId: devicePresetId.present
        ? devicePresetId.value
        : this.devicePresetId,
    startPath: startPath ?? this.startPath,
  );
  IdentityRow copyWithCompanion(IdentitiesCompanion data) {
    return IdentityRow(
      id: data.id.present ? data.id.value : this.id,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      name: data.name.present ? data.name.value : this.name,
      color: data.color.present ? data.color.value : this.color,
      isolationMode: data.isolationMode.present
          ? data.isolationMode.value
          : this.isolationMode,
      devicePresetId: data.devicePresetId.present
          ? data.devicePresetId.value
          : this.devicePresetId,
      startPath: data.startPath.present ? data.startPath.value : this.startPath,
    );
  }

  @override
  String toString() {
    return (StringBuffer('IdentityRow(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('isolationMode: $isolationMode, ')
          ..write('devicePresetId: $devicePresetId, ')
          ..write('startPath: $startPath')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    projectId,
    name,
    color,
    isolationMode,
    devicePresetId,
    startPath,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IdentityRow &&
          other.id == this.id &&
          other.projectId == this.projectId &&
          other.name == this.name &&
          other.color == this.color &&
          other.isolationMode == this.isolationMode &&
          other.devicePresetId == this.devicePresetId &&
          other.startPath == this.startPath);
}

class IdentitiesCompanion extends UpdateCompanion<IdentityRow> {
  final Value<String> id;
  final Value<String> projectId;
  final Value<String> name;
  final Value<String> color;
  final Value<String> isolationMode;
  final Value<String?> devicePresetId;
  final Value<String> startPath;
  final Value<int> rowid;
  const IdentitiesCompanion({
    this.id = const Value.absent(),
    this.projectId = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
    this.isolationMode = const Value.absent(),
    this.devicePresetId = const Value.absent(),
    this.startPath = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  IdentitiesCompanion.insert({
    required String id,
    required String projectId,
    required String name,
    required String color,
    required String isolationMode,
    this.devicePresetId = const Value.absent(),
    this.startPath = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       projectId = Value(projectId),
       name = Value(name),
       color = Value(color),
       isolationMode = Value(isolationMode);
  static Insertable<IdentityRow> custom({
    Expression<String>? id,
    Expression<String>? projectId,
    Expression<String>? name,
    Expression<String>? color,
    Expression<String>? isolationMode,
    Expression<String>? devicePresetId,
    Expression<String>? startPath,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (projectId != null) 'project_id': projectId,
      if (name != null) 'name': name,
      if (color != null) 'color': color,
      if (isolationMode != null) 'isolation_mode': isolationMode,
      if (devicePresetId != null) 'device_preset_id': devicePresetId,
      if (startPath != null) 'start_path': startPath,
      if (rowid != null) 'rowid': rowid,
    });
  }

  IdentitiesCompanion copyWith({
    Value<String>? id,
    Value<String>? projectId,
    Value<String>? name,
    Value<String>? color,
    Value<String>? isolationMode,
    Value<String?>? devicePresetId,
    Value<String>? startPath,
    Value<int>? rowid,
  }) {
    return IdentitiesCompanion(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      name: name ?? this.name,
      color: color ?? this.color,
      isolationMode: isolationMode ?? this.isolationMode,
      devicePresetId: devicePresetId ?? this.devicePresetId,
      startPath: startPath ?? this.startPath,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (isolationMode.present) {
      map['isolation_mode'] = Variable<String>(isolationMode.value);
    }
    if (devicePresetId.present) {
      map['device_preset_id'] = Variable<String>(devicePresetId.value);
    }
    if (startPath.present) {
      map['start_path'] = Variable<String>(startPath.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IdentitiesCompanion(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('isolationMode: $isolationMode, ')
          ..write('devicePresetId: $devicePresetId, ')
          ..write('startPath: $startPath, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SavedWorkspacesTable extends SavedWorkspaces
    with TableInfo<$SavedWorkspacesTable, WorkspaceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavedWorkspacesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES projects (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _viewportXMeta = const VerificationMeta(
    'viewportX',
  );
  @override
  late final GeneratedColumn<double> viewportX = GeneratedColumn<double>(
    'viewport_x',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _viewportYMeta = const VerificationMeta(
    'viewportY',
  );
  @override
  late final GeneratedColumn<double> viewportY = GeneratedColumn<double>(
    'viewport_y',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _zoomMeta = const VerificationMeta('zoom');
  @override
  late final GeneratedColumn<double> zoom = GeneratedColumn<double>(
    'zoom',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _layoutModeMeta = const VerificationMeta(
    'layoutMode',
  );
  @override
  late final GeneratedColumn<String> layoutMode = GeneratedColumn<String>(
    'layout_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('canvas'),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    projectId,
    name,
    viewportX,
    viewportY,
    zoom,
    layoutMode,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'saved_workspaces';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkspaceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_projectIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('viewport_x')) {
      context.handle(
        _viewportXMeta,
        viewportX.isAcceptableOrUnknown(data['viewport_x']!, _viewportXMeta),
      );
    }
    if (data.containsKey('viewport_y')) {
      context.handle(
        _viewportYMeta,
        viewportY.isAcceptableOrUnknown(data['viewport_y']!, _viewportYMeta),
      );
    }
    if (data.containsKey('zoom')) {
      context.handle(
        _zoomMeta,
        zoom.isAcceptableOrUnknown(data['zoom']!, _zoomMeta),
      );
    }
    if (data.containsKey('layout_mode')) {
      context.handle(
        _layoutModeMeta,
        layoutMode.isAcceptableOrUnknown(data['layout_mode']!, _layoutModeMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {projectId, name},
  ];
  @override
  WorkspaceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkspaceRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      viewportX: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}viewport_x'],
      )!,
      viewportY: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}viewport_y'],
      )!,
      zoom: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}zoom'],
      )!,
      layoutMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}layout_mode'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SavedWorkspacesTable createAlias(String alias) {
    return $SavedWorkspacesTable(attachedDatabase, alias);
  }
}

class WorkspaceRow extends DataClass implements Insertable<WorkspaceRow> {
  final String id;
  final String projectId;
  final String name;
  final double viewportX;
  final double viewportY;
  final double zoom;
  final String layoutMode;
  final int updatedAt;
  const WorkspaceRow({
    required this.id,
    required this.projectId,
    required this.name,
    required this.viewportX,
    required this.viewportY,
    required this.zoom,
    required this.layoutMode,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['project_id'] = Variable<String>(projectId);
    map['name'] = Variable<String>(name);
    map['viewport_x'] = Variable<double>(viewportX);
    map['viewport_y'] = Variable<double>(viewportY);
    map['zoom'] = Variable<double>(zoom);
    map['layout_mode'] = Variable<String>(layoutMode);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  SavedWorkspacesCompanion toCompanion(bool nullToAbsent) {
    return SavedWorkspacesCompanion(
      id: Value(id),
      projectId: Value(projectId),
      name: Value(name),
      viewportX: Value(viewportX),
      viewportY: Value(viewportY),
      zoom: Value(zoom),
      layoutMode: Value(layoutMode),
      updatedAt: Value(updatedAt),
    );
  }

  factory WorkspaceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkspaceRow(
      id: serializer.fromJson<String>(json['id']),
      projectId: serializer.fromJson<String>(json['projectId']),
      name: serializer.fromJson<String>(json['name']),
      viewportX: serializer.fromJson<double>(json['viewportX']),
      viewportY: serializer.fromJson<double>(json['viewportY']),
      zoom: serializer.fromJson<double>(json['zoom']),
      layoutMode: serializer.fromJson<String>(json['layoutMode']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'projectId': serializer.toJson<String>(projectId),
      'name': serializer.toJson<String>(name),
      'viewportX': serializer.toJson<double>(viewportX),
      'viewportY': serializer.toJson<double>(viewportY),
      'zoom': serializer.toJson<double>(zoom),
      'layoutMode': serializer.toJson<String>(layoutMode),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  WorkspaceRow copyWith({
    String? id,
    String? projectId,
    String? name,
    double? viewportX,
    double? viewportY,
    double? zoom,
    String? layoutMode,
    int? updatedAt,
  }) => WorkspaceRow(
    id: id ?? this.id,
    projectId: projectId ?? this.projectId,
    name: name ?? this.name,
    viewportX: viewportX ?? this.viewportX,
    viewportY: viewportY ?? this.viewportY,
    zoom: zoom ?? this.zoom,
    layoutMode: layoutMode ?? this.layoutMode,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  WorkspaceRow copyWithCompanion(SavedWorkspacesCompanion data) {
    return WorkspaceRow(
      id: data.id.present ? data.id.value : this.id,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      name: data.name.present ? data.name.value : this.name,
      viewportX: data.viewportX.present ? data.viewportX.value : this.viewportX,
      viewportY: data.viewportY.present ? data.viewportY.value : this.viewportY,
      zoom: data.zoom.present ? data.zoom.value : this.zoom,
      layoutMode: data.layoutMode.present
          ? data.layoutMode.value
          : this.layoutMode,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkspaceRow(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('name: $name, ')
          ..write('viewportX: $viewportX, ')
          ..write('viewportY: $viewportY, ')
          ..write('zoom: $zoom, ')
          ..write('layoutMode: $layoutMode, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    projectId,
    name,
    viewportX,
    viewportY,
    zoom,
    layoutMode,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkspaceRow &&
          other.id == this.id &&
          other.projectId == this.projectId &&
          other.name == this.name &&
          other.viewportX == this.viewportX &&
          other.viewportY == this.viewportY &&
          other.zoom == this.zoom &&
          other.layoutMode == this.layoutMode &&
          other.updatedAt == this.updatedAt);
}

class SavedWorkspacesCompanion extends UpdateCompanion<WorkspaceRow> {
  final Value<String> id;
  final Value<String> projectId;
  final Value<String> name;
  final Value<double> viewportX;
  final Value<double> viewportY;
  final Value<double> zoom;
  final Value<String> layoutMode;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const SavedWorkspacesCompanion({
    this.id = const Value.absent(),
    this.projectId = const Value.absent(),
    this.name = const Value.absent(),
    this.viewportX = const Value.absent(),
    this.viewportY = const Value.absent(),
    this.zoom = const Value.absent(),
    this.layoutMode = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SavedWorkspacesCompanion.insert({
    required String id,
    required String projectId,
    required String name,
    this.viewportX = const Value.absent(),
    this.viewportY = const Value.absent(),
    this.zoom = const Value.absent(),
    this.layoutMode = const Value.absent(),
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       projectId = Value(projectId),
       name = Value(name),
       updatedAt = Value(updatedAt);
  static Insertable<WorkspaceRow> custom({
    Expression<String>? id,
    Expression<String>? projectId,
    Expression<String>? name,
    Expression<double>? viewportX,
    Expression<double>? viewportY,
    Expression<double>? zoom,
    Expression<String>? layoutMode,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (projectId != null) 'project_id': projectId,
      if (name != null) 'name': name,
      if (viewportX != null) 'viewport_x': viewportX,
      if (viewportY != null) 'viewport_y': viewportY,
      if (zoom != null) 'zoom': zoom,
      if (layoutMode != null) 'layout_mode': layoutMode,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SavedWorkspacesCompanion copyWith({
    Value<String>? id,
    Value<String>? projectId,
    Value<String>? name,
    Value<double>? viewportX,
    Value<double>? viewportY,
    Value<double>? zoom,
    Value<String>? layoutMode,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return SavedWorkspacesCompanion(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      name: name ?? this.name,
      viewportX: viewportX ?? this.viewportX,
      viewportY: viewportY ?? this.viewportY,
      zoom: zoom ?? this.zoom,
      layoutMode: layoutMode ?? this.layoutMode,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (viewportX.present) {
      map['viewport_x'] = Variable<double>(viewportX.value);
    }
    if (viewportY.present) {
      map['viewport_y'] = Variable<double>(viewportY.value);
    }
    if (zoom.present) {
      map['zoom'] = Variable<double>(zoom.value);
    }
    if (layoutMode.present) {
      map['layout_mode'] = Variable<String>(layoutMode.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavedWorkspacesCompanion(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('name: $name, ')
          ..write('viewportX: $viewportX, ')
          ..write('viewportY: $viewportY, ')
          ..write('zoom: $zoom, ')
          ..write('layoutMode: $layoutMode, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SavedPanelLayoutsTable extends SavedPanelLayouts
    with TableInfo<$SavedPanelLayoutsTable, PanelRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavedPanelLayoutsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES saved_workspaces (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _identityIdMeta = const VerificationMeta(
    'identityId',
  );
  @override
  late final GeneratedColumn<String> identityId = GeneratedColumn<String>(
    'identity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES identities (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _xMeta = const VerificationMeta('x');
  @override
  late final GeneratedColumn<double> x = GeneratedColumn<double>(
    'x',
    aliasedName,
    false,
    check: () => ComparableExpr(x).isBiggerOrEqualValue(0),
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _yMeta = const VerificationMeta('y');
  @override
  late final GeneratedColumn<double> y = GeneratedColumn<double>(
    'y',
    aliasedName,
    false,
    check: () => ComparableExpr(y).isBiggerOrEqualValue(0),
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<double> width = GeneratedColumn<double>(
    'width',
    aliasedName,
    false,
    check: () => ComparableExpr(width).isBiggerOrEqualValue(320),
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<double> height = GeneratedColumn<double>(
    'height',
    aliasedName,
    false,
    check: () => ComparableExpr(height).isBiggerOrEqualValue(240),
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _zIndexMeta = const VerificationMeta('zIndex');
  @override
  late final GeneratedColumn<int> zIndex = GeneratedColumn<int>(
    'z_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _minimizedMeta = const VerificationMeta(
    'minimized',
  );
  @override
  late final GeneratedColumn<bool> minimized = GeneratedColumn<bool>(
    'minimized',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("minimized" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _detachedMeta = const VerificationMeta(
    'detached',
  );
  @override
  late final GeneratedColumn<bool> detached = GeneratedColumn<bool>(
    'detached',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("detached" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    workspaceId,
    identityId,
    x,
    y,
    width,
    height,
    zIndex,
    minimized,
    detached,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'saved_panel_layouts';
  @override
  VerificationContext validateIntegrity(
    Insertable<PanelRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('identity_id')) {
      context.handle(
        _identityIdMeta,
        identityId.isAcceptableOrUnknown(data['identity_id']!, _identityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_identityIdMeta);
    }
    if (data.containsKey('x')) {
      context.handle(_xMeta, x.isAcceptableOrUnknown(data['x']!, _xMeta));
    } else if (isInserting) {
      context.missing(_xMeta);
    }
    if (data.containsKey('y')) {
      context.handle(_yMeta, y.isAcceptableOrUnknown(data['y']!, _yMeta));
    } else if (isInserting) {
      context.missing(_yMeta);
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    } else if (isInserting) {
      context.missing(_widthMeta);
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    } else if (isInserting) {
      context.missing(_heightMeta);
    }
    if (data.containsKey('z_index')) {
      context.handle(
        _zIndexMeta,
        zIndex.isAcceptableOrUnknown(data['z_index']!, _zIndexMeta),
      );
    }
    if (data.containsKey('minimized')) {
      context.handle(
        _minimizedMeta,
        minimized.isAcceptableOrUnknown(data['minimized']!, _minimizedMeta),
      );
    }
    if (data.containsKey('detached')) {
      context.handle(
        _detachedMeta,
        detached.isAcceptableOrUnknown(data['detached']!, _detachedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {workspaceId, identityId};
  @override
  PanelRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PanelRow(
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      identityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identity_id'],
      )!,
      x: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}x'],
      )!,
      y: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}y'],
      )!,
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}width'],
      )!,
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}height'],
      )!,
      zIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}z_index'],
      )!,
      minimized: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}minimized'],
      )!,
      detached: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}detached'],
      )!,
    );
  }

  @override
  $SavedPanelLayoutsTable createAlias(String alias) {
    return $SavedPanelLayoutsTable(attachedDatabase, alias);
  }
}

class PanelRow extends DataClass implements Insertable<PanelRow> {
  final String workspaceId;
  final String identityId;
  final double x;
  final double y;
  final double width;
  final double height;
  final int zIndex;
  final bool minimized;
  final bool detached;
  const PanelRow({
    required this.workspaceId,
    required this.identityId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.zIndex,
    required this.minimized,
    required this.detached,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['workspace_id'] = Variable<String>(workspaceId);
    map['identity_id'] = Variable<String>(identityId);
    map['x'] = Variable<double>(x);
    map['y'] = Variable<double>(y);
    map['width'] = Variable<double>(width);
    map['height'] = Variable<double>(height);
    map['z_index'] = Variable<int>(zIndex);
    map['minimized'] = Variable<bool>(minimized);
    map['detached'] = Variable<bool>(detached);
    return map;
  }

  SavedPanelLayoutsCompanion toCompanion(bool nullToAbsent) {
    return SavedPanelLayoutsCompanion(
      workspaceId: Value(workspaceId),
      identityId: Value(identityId),
      x: Value(x),
      y: Value(y),
      width: Value(width),
      height: Value(height),
      zIndex: Value(zIndex),
      minimized: Value(minimized),
      detached: Value(detached),
    );
  }

  factory PanelRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PanelRow(
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      identityId: serializer.fromJson<String>(json['identityId']),
      x: serializer.fromJson<double>(json['x']),
      y: serializer.fromJson<double>(json['y']),
      width: serializer.fromJson<double>(json['width']),
      height: serializer.fromJson<double>(json['height']),
      zIndex: serializer.fromJson<int>(json['zIndex']),
      minimized: serializer.fromJson<bool>(json['minimized']),
      detached: serializer.fromJson<bool>(json['detached']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'workspaceId': serializer.toJson<String>(workspaceId),
      'identityId': serializer.toJson<String>(identityId),
      'x': serializer.toJson<double>(x),
      'y': serializer.toJson<double>(y),
      'width': serializer.toJson<double>(width),
      'height': serializer.toJson<double>(height),
      'zIndex': serializer.toJson<int>(zIndex),
      'minimized': serializer.toJson<bool>(minimized),
      'detached': serializer.toJson<bool>(detached),
    };
  }

  PanelRow copyWith({
    String? workspaceId,
    String? identityId,
    double? x,
    double? y,
    double? width,
    double? height,
    int? zIndex,
    bool? minimized,
    bool? detached,
  }) => PanelRow(
    workspaceId: workspaceId ?? this.workspaceId,
    identityId: identityId ?? this.identityId,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    zIndex: zIndex ?? this.zIndex,
    minimized: minimized ?? this.minimized,
    detached: detached ?? this.detached,
  );
  PanelRow copyWithCompanion(SavedPanelLayoutsCompanion data) {
    return PanelRow(
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      identityId: data.identityId.present
          ? data.identityId.value
          : this.identityId,
      x: data.x.present ? data.x.value : this.x,
      y: data.y.present ? data.y.value : this.y,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      zIndex: data.zIndex.present ? data.zIndex.value : this.zIndex,
      minimized: data.minimized.present ? data.minimized.value : this.minimized,
      detached: data.detached.present ? data.detached.value : this.detached,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PanelRow(')
          ..write('workspaceId: $workspaceId, ')
          ..write('identityId: $identityId, ')
          ..write('x: $x, ')
          ..write('y: $y, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('zIndex: $zIndex, ')
          ..write('minimized: $minimized, ')
          ..write('detached: $detached')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    workspaceId,
    identityId,
    x,
    y,
    width,
    height,
    zIndex,
    minimized,
    detached,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PanelRow &&
          other.workspaceId == this.workspaceId &&
          other.identityId == this.identityId &&
          other.x == this.x &&
          other.y == this.y &&
          other.width == this.width &&
          other.height == this.height &&
          other.zIndex == this.zIndex &&
          other.minimized == this.minimized &&
          other.detached == this.detached);
}

class SavedPanelLayoutsCompanion extends UpdateCompanion<PanelRow> {
  final Value<String> workspaceId;
  final Value<String> identityId;
  final Value<double> x;
  final Value<double> y;
  final Value<double> width;
  final Value<double> height;
  final Value<int> zIndex;
  final Value<bool> minimized;
  final Value<bool> detached;
  final Value<int> rowid;
  const SavedPanelLayoutsCompanion({
    this.workspaceId = const Value.absent(),
    this.identityId = const Value.absent(),
    this.x = const Value.absent(),
    this.y = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.zIndex = const Value.absent(),
    this.minimized = const Value.absent(),
    this.detached = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SavedPanelLayoutsCompanion.insert({
    required String workspaceId,
    required String identityId,
    required double x,
    required double y,
    required double width,
    required double height,
    this.zIndex = const Value.absent(),
    this.minimized = const Value.absent(),
    this.detached = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : workspaceId = Value(workspaceId),
       identityId = Value(identityId),
       x = Value(x),
       y = Value(y),
       width = Value(width),
       height = Value(height);
  static Insertable<PanelRow> custom({
    Expression<String>? workspaceId,
    Expression<String>? identityId,
    Expression<double>? x,
    Expression<double>? y,
    Expression<double>? width,
    Expression<double>? height,
    Expression<int>? zIndex,
    Expression<bool>? minimized,
    Expression<bool>? detached,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (identityId != null) 'identity_id': identityId,
      if (x != null) 'x': x,
      if (y != null) 'y': y,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (zIndex != null) 'z_index': zIndex,
      if (minimized != null) 'minimized': minimized,
      if (detached != null) 'detached': detached,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SavedPanelLayoutsCompanion copyWith({
    Value<String>? workspaceId,
    Value<String>? identityId,
    Value<double>? x,
    Value<double>? y,
    Value<double>? width,
    Value<double>? height,
    Value<int>? zIndex,
    Value<bool>? minimized,
    Value<bool>? detached,
    Value<int>? rowid,
  }) {
    return SavedPanelLayoutsCompanion(
      workspaceId: workspaceId ?? this.workspaceId,
      identityId: identityId ?? this.identityId,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      zIndex: zIndex ?? this.zIndex,
      minimized: minimized ?? this.minimized,
      detached: detached ?? this.detached,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (identityId.present) {
      map['identity_id'] = Variable<String>(identityId.value);
    }
    if (x.present) {
      map['x'] = Variable<double>(x.value);
    }
    if (y.present) {
      map['y'] = Variable<double>(y.value);
    }
    if (width.present) {
      map['width'] = Variable<double>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<double>(height.value);
    }
    if (zIndex.present) {
      map['z_index'] = Variable<int>(zIndex.value);
    }
    if (minimized.present) {
      map['minimized'] = Variable<bool>(minimized.value);
    }
    if (detached.present) {
      map['detached'] = Variable<bool>(detached.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavedPanelLayoutsCompanion(')
          ..write('workspaceId: $workspaceId, ')
          ..write('identityId: $identityId, ')
          ..write('x: $x, ')
          ..write('y: $y, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('zIndex: $zIndex, ')
          ..write('minimized: $minimized, ')
          ..write('detached: $detached, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CustomDevicePresetsTable extends CustomDevicePresets
    with TableInfo<$CustomDevicePresetsTable, CustomDevicePresetRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CustomDevicePresetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    false,
    check: () => ComparableExpr(width).isBiggerOrEqualValue(120),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    false,
    check: () => ComparableExpr(height).isBiggerOrEqualValue(120),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, width, height, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'custom_device_presets';
  @override
  VerificationContext validateIntegrity(
    Insertable<CustomDevicePresetRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    } else if (isInserting) {
      context.missing(_widthMeta);
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    } else if (isInserting) {
      context.missing(_heightMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CustomDevicePresetRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CustomDevicePresetRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      )!,
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $CustomDevicePresetsTable createAlias(String alias) {
    return $CustomDevicePresetsTable(attachedDatabase, alias);
  }
}

class CustomDevicePresetRow extends DataClass
    implements Insertable<CustomDevicePresetRow> {
  final String id;
  final String name;
  final int width;
  final int height;
  final int createdAt;
  const CustomDevicePresetRow({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['width'] = Variable<int>(width);
    map['height'] = Variable<int>(height);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  CustomDevicePresetsCompanion toCompanion(bool nullToAbsent) {
    return CustomDevicePresetsCompanion(
      id: Value(id),
      name: Value(name),
      width: Value(width),
      height: Value(height),
      createdAt: Value(createdAt),
    );
  }

  factory CustomDevicePresetRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CustomDevicePresetRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      width: serializer.fromJson<int>(json['width']),
      height: serializer.fromJson<int>(json['height']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'width': serializer.toJson<int>(width),
      'height': serializer.toJson<int>(height),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  CustomDevicePresetRow copyWith({
    String? id,
    String? name,
    int? width,
    int? height,
    int? createdAt,
  }) => CustomDevicePresetRow(
    id: id ?? this.id,
    name: name ?? this.name,
    width: width ?? this.width,
    height: height ?? this.height,
    createdAt: createdAt ?? this.createdAt,
  );
  CustomDevicePresetRow copyWithCompanion(CustomDevicePresetsCompanion data) {
    return CustomDevicePresetRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CustomDevicePresetRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, width, height, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CustomDevicePresetRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.width == this.width &&
          other.height == this.height &&
          other.createdAt == this.createdAt);
}

class CustomDevicePresetsCompanion
    extends UpdateCompanion<CustomDevicePresetRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> width;
  final Value<int> height;
  final Value<int> createdAt;
  final Value<int> rowid;
  const CustomDevicePresetsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CustomDevicePresetsCompanion.insert({
    required String id,
    required String name,
    required int width,
    required int height,
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       width = Value(width),
       height = Value(height),
       createdAt = Value(createdAt);
  static Insertable<CustomDevicePresetRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? width,
    Expression<int>? height,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CustomDevicePresetsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? width,
    Value<int>? height,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return CustomDevicePresetsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      width: width ?? this.width,
      height: height ?? this.height,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CustomDevicePresetsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$RelayDatabase extends GeneratedDatabase {
  _$RelayDatabase(QueryExecutor e) : super(e);
  $RelayDatabaseManager get managers => $RelayDatabaseManager(this);
  late final $ProjectsTable projects = $ProjectsTable(this);
  late final $IdentitiesTable identities = $IdentitiesTable(this);
  late final $SavedWorkspacesTable savedWorkspaces = $SavedWorkspacesTable(
    this,
  );
  late final $SavedPanelLayoutsTable savedPanelLayouts =
      $SavedPanelLayoutsTable(this);
  late final $CustomDevicePresetsTable customDevicePresets =
      $CustomDevicePresetsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    projects,
    identities,
    savedWorkspaces,
    savedPanelLayouts,
    customDevicePresets,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'projects',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('identities', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'projects',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('saved_workspaces', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'saved_workspaces',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('saved_panel_layouts', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'identities',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('saved_panel_layouts', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$ProjectsTableCreateCompanionBuilder =
    ProjectsCompanion Function({
      required String id,
      required String name,
      required String targetUrl,
      Value<bool> allowPrivateNetwork,
      required int createdAt,
      required int updatedAt,
      Value<String> defaultLayoutMode,
      Value<int> rowid,
    });
typedef $$ProjectsTableUpdateCompanionBuilder =
    ProjectsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> targetUrl,
      Value<bool> allowPrivateNetwork,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<String> defaultLayoutMode,
      Value<int> rowid,
    });

final class $$ProjectsTableReferences
    extends BaseReferences<_$RelayDatabase, $ProjectsTable, ProjectRow> {
  $$ProjectsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$IdentitiesTable, List<IdentityRow>>
  _identitiesRefsTable(_$RelayDatabase db) => MultiTypedResultKey.fromTable(
    db.identities,
    aliasName: 'projects__id__identities__project_id',
  );

  $$IdentitiesTableProcessedTableManager get identitiesRefs {
    final manager = $$IdentitiesTableTableManager(
      $_db,
      $_db.identities,
    ).filter((f) => f.projectId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_identitiesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SavedWorkspacesTable, List<WorkspaceRow>>
  _savedWorkspacesRefsTable(_$RelayDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.savedWorkspaces,
        aliasName: 'projects__id__saved_workspaces__project_id',
      );

  $$SavedWorkspacesTableProcessedTableManager get savedWorkspacesRefs {
    final manager = $$SavedWorkspacesTableTableManager(
      $_db,
      $_db.savedWorkspaces,
    ).filter((f) => f.projectId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _savedWorkspacesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ProjectsTableFilterComposer
    extends Composer<_$RelayDatabase, $ProjectsTable> {
  $$ProjectsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetUrl => $composableBuilder(
    column: $table.targetUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get allowPrivateNetwork => $composableBuilder(
    column: $table.allowPrivateNetwork,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get defaultLayoutMode => $composableBuilder(
    column: $table.defaultLayoutMode,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> identitiesRefs(
    Expression<bool> Function($$IdentitiesTableFilterComposer f) f,
  ) {
    final $$IdentitiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.identities,
      getReferencedColumn: (t) => t.projectId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IdentitiesTableFilterComposer(
            $db: $db,
            $table: $db.identities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> savedWorkspacesRefs(
    Expression<bool> Function($$SavedWorkspacesTableFilterComposer f) f,
  ) {
    final $$SavedWorkspacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.savedWorkspaces,
      getReferencedColumn: (t) => t.projectId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SavedWorkspacesTableFilterComposer(
            $db: $db,
            $table: $db.savedWorkspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ProjectsTableOrderingComposer
    extends Composer<_$RelayDatabase, $ProjectsTable> {
  $$ProjectsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetUrl => $composableBuilder(
    column: $table.targetUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get allowPrivateNetwork => $composableBuilder(
    column: $table.allowPrivateNetwork,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get defaultLayoutMode => $composableBuilder(
    column: $table.defaultLayoutMode,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProjectsTableAnnotationComposer
    extends Composer<_$RelayDatabase, $ProjectsTable> {
  $$ProjectsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get targetUrl =>
      $composableBuilder(column: $table.targetUrl, builder: (column) => column);

  GeneratedColumn<bool> get allowPrivateNetwork => $composableBuilder(
    column: $table.allowPrivateNetwork,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get defaultLayoutMode => $composableBuilder(
    column: $table.defaultLayoutMode,
    builder: (column) => column,
  );

  Expression<T> identitiesRefs<T extends Object>(
    Expression<T> Function($$IdentitiesTableAnnotationComposer a) f,
  ) {
    final $$IdentitiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.identities,
      getReferencedColumn: (t) => t.projectId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IdentitiesTableAnnotationComposer(
            $db: $db,
            $table: $db.identities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> savedWorkspacesRefs<T extends Object>(
    Expression<T> Function($$SavedWorkspacesTableAnnotationComposer a) f,
  ) {
    final $$SavedWorkspacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.savedWorkspaces,
      getReferencedColumn: (t) => t.projectId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SavedWorkspacesTableAnnotationComposer(
            $db: $db,
            $table: $db.savedWorkspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ProjectsTableTableManager
    extends
        RootTableManager<
          _$RelayDatabase,
          $ProjectsTable,
          ProjectRow,
          $$ProjectsTableFilterComposer,
          $$ProjectsTableOrderingComposer,
          $$ProjectsTableAnnotationComposer,
          $$ProjectsTableCreateCompanionBuilder,
          $$ProjectsTableUpdateCompanionBuilder,
          (ProjectRow, $$ProjectsTableReferences),
          ProjectRow,
          PrefetchHooks Function({
            bool identitiesRefs,
            bool savedWorkspacesRefs,
          })
        > {
  $$ProjectsTableTableManager(_$RelayDatabase db, $ProjectsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProjectsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProjectsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProjectsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> targetUrl = const Value.absent(),
                Value<bool> allowPrivateNetwork = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String> defaultLayoutMode = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProjectsCompanion(
                id: id,
                name: name,
                targetUrl: targetUrl,
                allowPrivateNetwork: allowPrivateNetwork,
                createdAt: createdAt,
                updatedAt: updatedAt,
                defaultLayoutMode: defaultLayoutMode,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String targetUrl,
                Value<bool> allowPrivateNetwork = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<String> defaultLayoutMode = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProjectsCompanion.insert(
                id: id,
                name: name,
                targetUrl: targetUrl,
                allowPrivateNetwork: allowPrivateNetwork,
                createdAt: createdAt,
                updatedAt: updatedAt,
                defaultLayoutMode: defaultLayoutMode,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ProjectsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({identitiesRefs = false, savedWorkspacesRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (identitiesRefs) db.identities,
                    if (savedWorkspacesRefs) db.savedWorkspaces,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (identitiesRefs)
                        await $_getPrefetchedData<
                          ProjectRow,
                          $ProjectsTable,
                          IdentityRow
                        >(
                          currentTable: table,
                          referencedTable: $$ProjectsTableReferences
                              ._identitiesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProjectsTableReferences(
                                db,
                                table,
                                p0,
                              ).identitiesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.projectId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (savedWorkspacesRefs)
                        await $_getPrefetchedData<
                          ProjectRow,
                          $ProjectsTable,
                          WorkspaceRow
                        >(
                          currentTable: table,
                          referencedTable: $$ProjectsTableReferences
                              ._savedWorkspacesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProjectsTableReferences(
                                db,
                                table,
                                p0,
                              ).savedWorkspacesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.projectId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ProjectsTableProcessedTableManager =
    ProcessedTableManager<
      _$RelayDatabase,
      $ProjectsTable,
      ProjectRow,
      $$ProjectsTableFilterComposer,
      $$ProjectsTableOrderingComposer,
      $$ProjectsTableAnnotationComposer,
      $$ProjectsTableCreateCompanionBuilder,
      $$ProjectsTableUpdateCompanionBuilder,
      (ProjectRow, $$ProjectsTableReferences),
      ProjectRow,
      PrefetchHooks Function({bool identitiesRefs, bool savedWorkspacesRefs})
    >;
typedef $$IdentitiesTableCreateCompanionBuilder =
    IdentitiesCompanion Function({
      required String id,
      required String projectId,
      required String name,
      required String color,
      required String isolationMode,
      Value<String?> devicePresetId,
      Value<String> startPath,
      Value<int> rowid,
    });
typedef $$IdentitiesTableUpdateCompanionBuilder =
    IdentitiesCompanion Function({
      Value<String> id,
      Value<String> projectId,
      Value<String> name,
      Value<String> color,
      Value<String> isolationMode,
      Value<String?> devicePresetId,
      Value<String> startPath,
      Value<int> rowid,
    });

final class $$IdentitiesTableReferences
    extends BaseReferences<_$RelayDatabase, $IdentitiesTable, IdentityRow> {
  $$IdentitiesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ProjectsTable _projectIdTable(_$RelayDatabase db) =>
      db.projects.createAlias('identities__project_id__projects__id');

  $$ProjectsTableProcessedTableManager get projectId {
    final $_column = $_itemColumn<String>('project_id')!;

    final manager = $$ProjectsTableTableManager(
      $_db,
      $_db.projects,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_projectIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$SavedPanelLayoutsTable, List<PanelRow>>
  _savedPanelLayoutsRefsTable(_$RelayDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.savedPanelLayouts,
        aliasName: 'identities__id__saved_panel_layouts__identity_id',
      );

  $$SavedPanelLayoutsTableProcessedTableManager get savedPanelLayoutsRefs {
    final manager = $$SavedPanelLayoutsTableTableManager(
      $_db,
      $_db.savedPanelLayouts,
    ).filter((f) => f.identityId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _savedPanelLayoutsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$IdentitiesTableFilterComposer
    extends Composer<_$RelayDatabase, $IdentitiesTable> {
  $$IdentitiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get isolationMode => $composableBuilder(
    column: $table.isolationMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get devicePresetId => $composableBuilder(
    column: $table.devicePresetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startPath => $composableBuilder(
    column: $table.startPath,
    builder: (column) => ColumnFilters(column),
  );

  $$ProjectsTableFilterComposer get projectId {
    final $$ProjectsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableFilterComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> savedPanelLayoutsRefs(
    Expression<bool> Function($$SavedPanelLayoutsTableFilterComposer f) f,
  ) {
    final $$SavedPanelLayoutsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.savedPanelLayouts,
      getReferencedColumn: (t) => t.identityId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SavedPanelLayoutsTableFilterComposer(
            $db: $db,
            $table: $db.savedPanelLayouts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$IdentitiesTableOrderingComposer
    extends Composer<_$RelayDatabase, $IdentitiesTable> {
  $$IdentitiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get isolationMode => $composableBuilder(
    column: $table.isolationMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get devicePresetId => $composableBuilder(
    column: $table.devicePresetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startPath => $composableBuilder(
    column: $table.startPath,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProjectsTableOrderingComposer get projectId {
    final $$ProjectsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableOrderingComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$IdentitiesTableAnnotationComposer
    extends Composer<_$RelayDatabase, $IdentitiesTable> {
  $$IdentitiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<String> get isolationMode => $composableBuilder(
    column: $table.isolationMode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get devicePresetId => $composableBuilder(
    column: $table.devicePresetId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get startPath =>
      $composableBuilder(column: $table.startPath, builder: (column) => column);

  $$ProjectsTableAnnotationComposer get projectId {
    final $$ProjectsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableAnnotationComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> savedPanelLayoutsRefs<T extends Object>(
    Expression<T> Function($$SavedPanelLayoutsTableAnnotationComposer a) f,
  ) {
    final $$SavedPanelLayoutsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.savedPanelLayouts,
          getReferencedColumn: (t) => t.identityId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$SavedPanelLayoutsTableAnnotationComposer(
                $db: $db,
                $table: $db.savedPanelLayouts,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$IdentitiesTableTableManager
    extends
        RootTableManager<
          _$RelayDatabase,
          $IdentitiesTable,
          IdentityRow,
          $$IdentitiesTableFilterComposer,
          $$IdentitiesTableOrderingComposer,
          $$IdentitiesTableAnnotationComposer,
          $$IdentitiesTableCreateCompanionBuilder,
          $$IdentitiesTableUpdateCompanionBuilder,
          (IdentityRow, $$IdentitiesTableReferences),
          IdentityRow,
          PrefetchHooks Function({bool projectId, bool savedPanelLayoutsRefs})
        > {
  $$IdentitiesTableTableManager(_$RelayDatabase db, $IdentitiesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$IdentitiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$IdentitiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$IdentitiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> projectId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<String> isolationMode = const Value.absent(),
                Value<String?> devicePresetId = const Value.absent(),
                Value<String> startPath = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => IdentitiesCompanion(
                id: id,
                projectId: projectId,
                name: name,
                color: color,
                isolationMode: isolationMode,
                devicePresetId: devicePresetId,
                startPath: startPath,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String projectId,
                required String name,
                required String color,
                required String isolationMode,
                Value<String?> devicePresetId = const Value.absent(),
                Value<String> startPath = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => IdentitiesCompanion.insert(
                id: id,
                projectId: projectId,
                name: name,
                color: color,
                isolationMode: isolationMode,
                devicePresetId: devicePresetId,
                startPath: startPath,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$IdentitiesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({projectId = false, savedPanelLayoutsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (savedPanelLayoutsRefs) db.savedPanelLayouts,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (projectId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.projectId,
                                    referencedTable: $$IdentitiesTableReferences
                                        ._projectIdTable(db),
                                    referencedColumn:
                                        $$IdentitiesTableReferences
                                            ._projectIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (savedPanelLayoutsRefs)
                        await $_getPrefetchedData<
                          IdentityRow,
                          $IdentitiesTable,
                          PanelRow
                        >(
                          currentTable: table,
                          referencedTable: $$IdentitiesTableReferences
                              ._savedPanelLayoutsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$IdentitiesTableReferences(
                                db,
                                table,
                                p0,
                              ).savedPanelLayoutsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.identityId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$IdentitiesTableProcessedTableManager =
    ProcessedTableManager<
      _$RelayDatabase,
      $IdentitiesTable,
      IdentityRow,
      $$IdentitiesTableFilterComposer,
      $$IdentitiesTableOrderingComposer,
      $$IdentitiesTableAnnotationComposer,
      $$IdentitiesTableCreateCompanionBuilder,
      $$IdentitiesTableUpdateCompanionBuilder,
      (IdentityRow, $$IdentitiesTableReferences),
      IdentityRow,
      PrefetchHooks Function({bool projectId, bool savedPanelLayoutsRefs})
    >;
typedef $$SavedWorkspacesTableCreateCompanionBuilder =
    SavedWorkspacesCompanion Function({
      required String id,
      required String projectId,
      required String name,
      Value<double> viewportX,
      Value<double> viewportY,
      Value<double> zoom,
      Value<String> layoutMode,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$SavedWorkspacesTableUpdateCompanionBuilder =
    SavedWorkspacesCompanion Function({
      Value<String> id,
      Value<String> projectId,
      Value<String> name,
      Value<double> viewportX,
      Value<double> viewportY,
      Value<double> zoom,
      Value<String> layoutMode,
      Value<int> updatedAt,
      Value<int> rowid,
    });

final class $$SavedWorkspacesTableReferences
    extends
        BaseReferences<_$RelayDatabase, $SavedWorkspacesTable, WorkspaceRow> {
  $$SavedWorkspacesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ProjectsTable _projectIdTable(_$RelayDatabase db) =>
      db.projects.createAlias('saved_workspaces__project_id__projects__id');

  $$ProjectsTableProcessedTableManager get projectId {
    final $_column = $_itemColumn<String>('project_id')!;

    final manager = $$ProjectsTableTableManager(
      $_db,
      $_db.projects,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_projectIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$SavedPanelLayoutsTable, List<PanelRow>>
  _savedPanelLayoutsRefsTable(_$RelayDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.savedPanelLayouts,
        aliasName: 'saved_workspaces__id__saved_panel_layouts__workspace_id',
      );

  $$SavedPanelLayoutsTableProcessedTableManager get savedPanelLayoutsRefs {
    final manager = $$SavedPanelLayoutsTableTableManager(
      $_db,
      $_db.savedPanelLayouts,
    ).filter((f) => f.workspaceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _savedPanelLayoutsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SavedWorkspacesTableFilterComposer
    extends Composer<_$RelayDatabase, $SavedWorkspacesTable> {
  $$SavedWorkspacesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get viewportX => $composableBuilder(
    column: $table.viewportX,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get viewportY => $composableBuilder(
    column: $table.viewportY,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get zoom => $composableBuilder(
    column: $table.zoom,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get layoutMode => $composableBuilder(
    column: $table.layoutMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ProjectsTableFilterComposer get projectId {
    final $$ProjectsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableFilterComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> savedPanelLayoutsRefs(
    Expression<bool> Function($$SavedPanelLayoutsTableFilterComposer f) f,
  ) {
    final $$SavedPanelLayoutsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.savedPanelLayouts,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SavedPanelLayoutsTableFilterComposer(
            $db: $db,
            $table: $db.savedPanelLayouts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SavedWorkspacesTableOrderingComposer
    extends Composer<_$RelayDatabase, $SavedWorkspacesTable> {
  $$SavedWorkspacesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get viewportX => $composableBuilder(
    column: $table.viewportX,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get viewportY => $composableBuilder(
    column: $table.viewportY,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get zoom => $composableBuilder(
    column: $table.zoom,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get layoutMode => $composableBuilder(
    column: $table.layoutMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProjectsTableOrderingComposer get projectId {
    final $$ProjectsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableOrderingComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SavedWorkspacesTableAnnotationComposer
    extends Composer<_$RelayDatabase, $SavedWorkspacesTable> {
  $$SavedWorkspacesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get viewportX =>
      $composableBuilder(column: $table.viewportX, builder: (column) => column);

  GeneratedColumn<double> get viewportY =>
      $composableBuilder(column: $table.viewportY, builder: (column) => column);

  GeneratedColumn<double> get zoom =>
      $composableBuilder(column: $table.zoom, builder: (column) => column);

  GeneratedColumn<String> get layoutMode => $composableBuilder(
    column: $table.layoutMode,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ProjectsTableAnnotationComposer get projectId {
    final $$ProjectsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableAnnotationComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> savedPanelLayoutsRefs<T extends Object>(
    Expression<T> Function($$SavedPanelLayoutsTableAnnotationComposer a) f,
  ) {
    final $$SavedPanelLayoutsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.savedPanelLayouts,
          getReferencedColumn: (t) => t.workspaceId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$SavedPanelLayoutsTableAnnotationComposer(
                $db: $db,
                $table: $db.savedPanelLayouts,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$SavedWorkspacesTableTableManager
    extends
        RootTableManager<
          _$RelayDatabase,
          $SavedWorkspacesTable,
          WorkspaceRow,
          $$SavedWorkspacesTableFilterComposer,
          $$SavedWorkspacesTableOrderingComposer,
          $$SavedWorkspacesTableAnnotationComposer,
          $$SavedWorkspacesTableCreateCompanionBuilder,
          $$SavedWorkspacesTableUpdateCompanionBuilder,
          (WorkspaceRow, $$SavedWorkspacesTableReferences),
          WorkspaceRow,
          PrefetchHooks Function({bool projectId, bool savedPanelLayoutsRefs})
        > {
  $$SavedWorkspacesTableTableManager(
    _$RelayDatabase db,
    $SavedWorkspacesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavedWorkspacesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SavedWorkspacesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SavedWorkspacesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> projectId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<double> viewportX = const Value.absent(),
                Value<double> viewportY = const Value.absent(),
                Value<double> zoom = const Value.absent(),
                Value<String> layoutMode = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SavedWorkspacesCompanion(
                id: id,
                projectId: projectId,
                name: name,
                viewportX: viewportX,
                viewportY: viewportY,
                zoom: zoom,
                layoutMode: layoutMode,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String projectId,
                required String name,
                Value<double> viewportX = const Value.absent(),
                Value<double> viewportY = const Value.absent(),
                Value<double> zoom = const Value.absent(),
                Value<String> layoutMode = const Value.absent(),
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SavedWorkspacesCompanion.insert(
                id: id,
                projectId: projectId,
                name: name,
                viewportX: viewportX,
                viewportY: viewportY,
                zoom: zoom,
                layoutMode: layoutMode,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SavedWorkspacesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({projectId = false, savedPanelLayoutsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (savedPanelLayoutsRefs) db.savedPanelLayouts,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (projectId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.projectId,
                                    referencedTable:
                                        $$SavedWorkspacesTableReferences
                                            ._projectIdTable(db),
                                    referencedColumn:
                                        $$SavedWorkspacesTableReferences
                                            ._projectIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (savedPanelLayoutsRefs)
                        await $_getPrefetchedData<
                          WorkspaceRow,
                          $SavedWorkspacesTable,
                          PanelRow
                        >(
                          currentTable: table,
                          referencedTable: $$SavedWorkspacesTableReferences
                              ._savedPanelLayoutsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SavedWorkspacesTableReferences(
                                db,
                                table,
                                p0,
                              ).savedPanelLayoutsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.workspaceId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$SavedWorkspacesTableProcessedTableManager =
    ProcessedTableManager<
      _$RelayDatabase,
      $SavedWorkspacesTable,
      WorkspaceRow,
      $$SavedWorkspacesTableFilterComposer,
      $$SavedWorkspacesTableOrderingComposer,
      $$SavedWorkspacesTableAnnotationComposer,
      $$SavedWorkspacesTableCreateCompanionBuilder,
      $$SavedWorkspacesTableUpdateCompanionBuilder,
      (WorkspaceRow, $$SavedWorkspacesTableReferences),
      WorkspaceRow,
      PrefetchHooks Function({bool projectId, bool savedPanelLayoutsRefs})
    >;
typedef $$SavedPanelLayoutsTableCreateCompanionBuilder =
    SavedPanelLayoutsCompanion Function({
      required String workspaceId,
      required String identityId,
      required double x,
      required double y,
      required double width,
      required double height,
      Value<int> zIndex,
      Value<bool> minimized,
      Value<bool> detached,
      Value<int> rowid,
    });
typedef $$SavedPanelLayoutsTableUpdateCompanionBuilder =
    SavedPanelLayoutsCompanion Function({
      Value<String> workspaceId,
      Value<String> identityId,
      Value<double> x,
      Value<double> y,
      Value<double> width,
      Value<double> height,
      Value<int> zIndex,
      Value<bool> minimized,
      Value<bool> detached,
      Value<int> rowid,
    });

final class $$SavedPanelLayoutsTableReferences
    extends BaseReferences<_$RelayDatabase, $SavedPanelLayoutsTable, PanelRow> {
  $$SavedPanelLayoutsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SavedWorkspacesTable _workspaceIdTable(_$RelayDatabase db) => db
      .savedWorkspaces
      .createAlias('saved_panel_layouts__workspace_id__saved_workspaces__id');

  $$SavedWorkspacesTableProcessedTableManager get workspaceId {
    final $_column = $_itemColumn<String>('workspace_id')!;

    final manager = $$SavedWorkspacesTableTableManager(
      $_db,
      $_db.savedWorkspaces,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_workspaceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $IdentitiesTable _identityIdTable(_$RelayDatabase db) => db.identities
      .createAlias('saved_panel_layouts__identity_id__identities__id');

  $$IdentitiesTableProcessedTableManager get identityId {
    final $_column = $_itemColumn<String>('identity_id')!;

    final manager = $$IdentitiesTableTableManager(
      $_db,
      $_db.identities,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_identityIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SavedPanelLayoutsTableFilterComposer
    extends Composer<_$RelayDatabase, $SavedPanelLayoutsTable> {
  $$SavedPanelLayoutsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<double> get x => $composableBuilder(
    column: $table.x,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get y => $composableBuilder(
    column: $table.y,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get zIndex => $composableBuilder(
    column: $table.zIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get minimized => $composableBuilder(
    column: $table.minimized,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get detached => $composableBuilder(
    column: $table.detached,
    builder: (column) => ColumnFilters(column),
  );

  $$SavedWorkspacesTableFilterComposer get workspaceId {
    final $$SavedWorkspacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.savedWorkspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SavedWorkspacesTableFilterComposer(
            $db: $db,
            $table: $db.savedWorkspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$IdentitiesTableFilterComposer get identityId {
    final $$IdentitiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.identityId,
      referencedTable: $db.identities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IdentitiesTableFilterComposer(
            $db: $db,
            $table: $db.identities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SavedPanelLayoutsTableOrderingComposer
    extends Composer<_$RelayDatabase, $SavedPanelLayoutsTable> {
  $$SavedPanelLayoutsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<double> get x => $composableBuilder(
    column: $table.x,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get y => $composableBuilder(
    column: $table.y,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get zIndex => $composableBuilder(
    column: $table.zIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get minimized => $composableBuilder(
    column: $table.minimized,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get detached => $composableBuilder(
    column: $table.detached,
    builder: (column) => ColumnOrderings(column),
  );

  $$SavedWorkspacesTableOrderingComposer get workspaceId {
    final $$SavedWorkspacesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.savedWorkspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SavedWorkspacesTableOrderingComposer(
            $db: $db,
            $table: $db.savedWorkspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$IdentitiesTableOrderingComposer get identityId {
    final $$IdentitiesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.identityId,
      referencedTable: $db.identities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IdentitiesTableOrderingComposer(
            $db: $db,
            $table: $db.identities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SavedPanelLayoutsTableAnnotationComposer
    extends Composer<_$RelayDatabase, $SavedPanelLayoutsTable> {
  $$SavedPanelLayoutsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<double> get x =>
      $composableBuilder(column: $table.x, builder: (column) => column);

  GeneratedColumn<double> get y =>
      $composableBuilder(column: $table.y, builder: (column) => column);

  GeneratedColumn<double> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<double> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<int> get zIndex =>
      $composableBuilder(column: $table.zIndex, builder: (column) => column);

  GeneratedColumn<bool> get minimized =>
      $composableBuilder(column: $table.minimized, builder: (column) => column);

  GeneratedColumn<bool> get detached =>
      $composableBuilder(column: $table.detached, builder: (column) => column);

  $$SavedWorkspacesTableAnnotationComposer get workspaceId {
    final $$SavedWorkspacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.savedWorkspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SavedWorkspacesTableAnnotationComposer(
            $db: $db,
            $table: $db.savedWorkspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$IdentitiesTableAnnotationComposer get identityId {
    final $$IdentitiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.identityId,
      referencedTable: $db.identities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IdentitiesTableAnnotationComposer(
            $db: $db,
            $table: $db.identities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SavedPanelLayoutsTableTableManager
    extends
        RootTableManager<
          _$RelayDatabase,
          $SavedPanelLayoutsTable,
          PanelRow,
          $$SavedPanelLayoutsTableFilterComposer,
          $$SavedPanelLayoutsTableOrderingComposer,
          $$SavedPanelLayoutsTableAnnotationComposer,
          $$SavedPanelLayoutsTableCreateCompanionBuilder,
          $$SavedPanelLayoutsTableUpdateCompanionBuilder,
          (PanelRow, $$SavedPanelLayoutsTableReferences),
          PanelRow,
          PrefetchHooks Function({bool workspaceId, bool identityId})
        > {
  $$SavedPanelLayoutsTableTableManager(
    _$RelayDatabase db,
    $SavedPanelLayoutsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavedPanelLayoutsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SavedPanelLayoutsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SavedPanelLayoutsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> workspaceId = const Value.absent(),
                Value<String> identityId = const Value.absent(),
                Value<double> x = const Value.absent(),
                Value<double> y = const Value.absent(),
                Value<double> width = const Value.absent(),
                Value<double> height = const Value.absent(),
                Value<int> zIndex = const Value.absent(),
                Value<bool> minimized = const Value.absent(),
                Value<bool> detached = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SavedPanelLayoutsCompanion(
                workspaceId: workspaceId,
                identityId: identityId,
                x: x,
                y: y,
                width: width,
                height: height,
                zIndex: zIndex,
                minimized: minimized,
                detached: detached,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String workspaceId,
                required String identityId,
                required double x,
                required double y,
                required double width,
                required double height,
                Value<int> zIndex = const Value.absent(),
                Value<bool> minimized = const Value.absent(),
                Value<bool> detached = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SavedPanelLayoutsCompanion.insert(
                workspaceId: workspaceId,
                identityId: identityId,
                x: x,
                y: y,
                width: width,
                height: height,
                zIndex: zIndex,
                minimized: minimized,
                detached: detached,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SavedPanelLayoutsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({workspaceId = false, identityId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (workspaceId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.workspaceId,
                                referencedTable:
                                    $$SavedPanelLayoutsTableReferences
                                        ._workspaceIdTable(db),
                                referencedColumn:
                                    $$SavedPanelLayoutsTableReferences
                                        ._workspaceIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (identityId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.identityId,
                                referencedTable:
                                    $$SavedPanelLayoutsTableReferences
                                        ._identityIdTable(db),
                                referencedColumn:
                                    $$SavedPanelLayoutsTableReferences
                                        ._identityIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SavedPanelLayoutsTableProcessedTableManager =
    ProcessedTableManager<
      _$RelayDatabase,
      $SavedPanelLayoutsTable,
      PanelRow,
      $$SavedPanelLayoutsTableFilterComposer,
      $$SavedPanelLayoutsTableOrderingComposer,
      $$SavedPanelLayoutsTableAnnotationComposer,
      $$SavedPanelLayoutsTableCreateCompanionBuilder,
      $$SavedPanelLayoutsTableUpdateCompanionBuilder,
      (PanelRow, $$SavedPanelLayoutsTableReferences),
      PanelRow,
      PrefetchHooks Function({bool workspaceId, bool identityId})
    >;
typedef $$CustomDevicePresetsTableCreateCompanionBuilder =
    CustomDevicePresetsCompanion Function({
      required String id,
      required String name,
      required int width,
      required int height,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$CustomDevicePresetsTableUpdateCompanionBuilder =
    CustomDevicePresetsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<int> width,
      Value<int> height,
      Value<int> createdAt,
      Value<int> rowid,
    });

class $$CustomDevicePresetsTableFilterComposer
    extends Composer<_$RelayDatabase, $CustomDevicePresetsTable> {
  $$CustomDevicePresetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CustomDevicePresetsTableOrderingComposer
    extends Composer<_$RelayDatabase, $CustomDevicePresetsTable> {
  $$CustomDevicePresetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CustomDevicePresetsTableAnnotationComposer
    extends Composer<_$RelayDatabase, $CustomDevicePresetsTable> {
  $$CustomDevicePresetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$CustomDevicePresetsTableTableManager
    extends
        RootTableManager<
          _$RelayDatabase,
          $CustomDevicePresetsTable,
          CustomDevicePresetRow,
          $$CustomDevicePresetsTableFilterComposer,
          $$CustomDevicePresetsTableOrderingComposer,
          $$CustomDevicePresetsTableAnnotationComposer,
          $$CustomDevicePresetsTableCreateCompanionBuilder,
          $$CustomDevicePresetsTableUpdateCompanionBuilder,
          (
            CustomDevicePresetRow,
            BaseReferences<
              _$RelayDatabase,
              $CustomDevicePresetsTable,
              CustomDevicePresetRow
            >,
          ),
          CustomDevicePresetRow,
          PrefetchHooks Function()
        > {
  $$CustomDevicePresetsTableTableManager(
    _$RelayDatabase db,
    $CustomDevicePresetsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CustomDevicePresetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CustomDevicePresetsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CustomDevicePresetsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> width = const Value.absent(),
                Value<int> height = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CustomDevicePresetsCompanion(
                id: id,
                name: name,
                width: width,
                height: height,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required int width,
                required int height,
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => CustomDevicePresetsCompanion.insert(
                id: id,
                name: name,
                width: width,
                height: height,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CustomDevicePresetsTableProcessedTableManager =
    ProcessedTableManager<
      _$RelayDatabase,
      $CustomDevicePresetsTable,
      CustomDevicePresetRow,
      $$CustomDevicePresetsTableFilterComposer,
      $$CustomDevicePresetsTableOrderingComposer,
      $$CustomDevicePresetsTableAnnotationComposer,
      $$CustomDevicePresetsTableCreateCompanionBuilder,
      $$CustomDevicePresetsTableUpdateCompanionBuilder,
      (
        CustomDevicePresetRow,
        BaseReferences<
          _$RelayDatabase,
          $CustomDevicePresetsTable,
          CustomDevicePresetRow
        >,
      ),
      CustomDevicePresetRow,
      PrefetchHooks Function()
    >;

class $RelayDatabaseManager {
  final _$RelayDatabase _db;
  $RelayDatabaseManager(this._db);
  $$ProjectsTableTableManager get projects =>
      $$ProjectsTableTableManager(_db, _db.projects);
  $$IdentitiesTableTableManager get identities =>
      $$IdentitiesTableTableManager(_db, _db.identities);
  $$SavedWorkspacesTableTableManager get savedWorkspaces =>
      $$SavedWorkspacesTableTableManager(_db, _db.savedWorkspaces);
  $$SavedPanelLayoutsTableTableManager get savedPanelLayouts =>
      $$SavedPanelLayoutsTableTableManager(_db, _db.savedPanelLayouts);
  $$CustomDevicePresetsTableTableManager get customDevicePresets =>
      $$CustomDevicePresetsTableTableManager(_db, _db.customDevicePresets);
}
