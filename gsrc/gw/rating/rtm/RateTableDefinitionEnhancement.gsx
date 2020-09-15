package gw.rating.rtm

uses gw.lang.reflect.IType
uses gw.lang.reflect.TypeSystem
uses gw.pcf.rating.flow.RateRoutineRateTablePopupHelper
uses gw.rating.rtm.query.RateQueryParam
uses java.lang.Integer
uses java.math.BigDecimal
uses java.util.ArrayList
uses java.util.Date
uses java.util.Map
uses gw.rating.flow.MultiFactorVariable

enhancement RateTableDefinitionEnhancement : entity.RateTableDefinition {

  private static property get TYPEMAP () : Map<RateTableDataType, Type> {
    return {
      RateTableDataType.TC_STRING   -> String,
      RateTableDataType.TC_INTEGER  -> Integer,
      RateTableDataType.TC_DECIMAL  -> BigDecimal,
      RateTableDataType.TC_DATE     -> Date,
      RateTableDataType.TC_BOOLEAN  -> Boolean
    }
  }


  property get AllColumns() : RateTableColumn[] {
    return SortedParameters.concat(SortedFactors)
  }

  property get SortedParameters() : RateTableColumn[] {
    return this.MatchOps*.Params.orderBy(\ col -> (col.SortOrder == null) ? 0 : col.SortOrder).toTypedArray()
  }

  property get SortedFactors() : RateTableColumn[] {
    return this.Factors.orderBy(\ col -> (col.SortOrder == null) ? 0 : col.SortOrder).toTypedArray()
  }

  function getFactorPhysicalColumnName() : String {
    return getFactorPhysicalColumnName(null)
  }

  function getFactorPhysicalColumnName(factorName : String) : String {
    if (factorName.length > 0) {
      var factor = this.Factors.firstWhere(\rtc -> rtc.ColumnName == factorName).PhysicalColumnName
      if (factor == null) {
        throw new gw.api.util.DisplayableException(displaykey.Web.Rating.RateTableDefinition.FactorNotFound(factorName, this.TableCode))
      }
      return factor
    } else {
      return this.Factors.single().PhysicalColumnName
    }
  }

  function getFactorIType(factorName : String) : IType {
    if (factorName == RateRoutineRateTablePopupHelper.AllFactorsCode) {
      return MultiFactorVariable
    } else {
      var rtDataType = this.Factors.singleWhere(\f -> f.ColumnName == factorName).ColumnType
      return TYPEMAP.get(rtDataType)
    }
  }

  function getFactorLabel(factorColumnName : String) : String {
    return this.Factors
      .where(\f -> f.ColumnName == factorColumnName)
      .single().ColumnLabel
  }

  function getMatchOpFor(inputParam : RateQueryParam) : RateTableMatchOp {
    return this.MatchOps.firstWhere(\ ops -> ops.hasSameNameAs(inputParam))
  }

  /*
   * Validates and returns the custom entity type specified in the rate table definition.
   * Returns default entity type if custom entity name is not defined in
   * the rate table definition.
   * For custom entity types, checks its existance in the type system and existance of the
   * RateTable foreign key that points to rate table definition.
   */
  property get FactorRowEntity() : IType {
    if (not hasValidEntity()) {
      throw new InvalidCustomRateTableException(displaykey.Web.Rating.Errors.CustomEntityDoesNotExist(this.EntityName))
    }
    return getEntityTypeClass()
  }

  property get QualifiedEntityName() : String {

    return "entity.${this.EntityName}"
  }

  function hasValidEntity() : boolean {
    var type = getEntityTypeClass()
    if (type == null) return false

    var prop = type.TypeInfo.getProperty("RateTable")
    if (prop == null or prop.FeatureType != RateTable) {
      return false
    }
    return true
  }

  function tablesUsingDefinition() : List<RateTable> {
    return gw.api.database.Query.make(RateTable).compare("Definition", Equals, this).select().toList()
  }

  function delete(){
    using(new java.util.concurrent.locks.ReentrantLock()){
      if(tablesUsingDefinition().Empty){
        this.Bundle.delete(this)
        this.Bundle.commit()
      }
      else{
        throw new gw.api.util.DisplayableException(displaykey.Web.Rating.RateTableDefinition.CannotDelete)
      }
    }
  }

  private function getEntityTypeClass() : IType {
    return TypeSystem.getByFullNameIfValid(this.QualifiedEntityName)
  }

  function availablePhysicalColumnsForDataType(dataType : typekey.RateTableDataType) : List<String> {
    var columnsForType: List<String>

    var allProperties = (FactorRowEntity as Type<KeyableBean>).EntityProperties.toList()
      .where(\ ep -> ep.ColumnInDb and not ep.Autogenerated)
    var propsByType = allProperties.partition(\ p -> p.FeatureType)
    var propsForType = propsByType.get(TYPEMAP.get(dataType))
    if (propsForType == null) {
      columnsForType = new ArrayList<String>()
    } else {
      columnsForType = propsForType*.Name.toList()
    }
    var allInUse = this.AllColumns*.PhysicalColumnName
    columnsForType.removeWhere(\ c -> allInUse.contains(c))

    return columnsForType
  }

  function resetPhysicalColumnNames() {
    this.AllColumns.each(\ col -> { col.PhysicalColumnName = "" })
  }

  function initializeCopy() : RateTableDefinition {
    var copiedTableDefinition : RateTableDefinition
    copiedTableDefinition = this.copy() as RateTableDefinition

    //Using AutoMap to allow adding things to the list without having to check for null
    var matchOpNamesMappedToCopiedArgumentSources : Map<String, List<RateTableArgumentSource>>
      = {}.toAutoMap(\ s -> new ArrayList<RateTableArgumentSource>())

    copiedTableDefinition.ArgumentSourceSets.each(\ copiedArgSrcSet -> {
      copiedArgSrcSet.RateTableArgumentSources.each(\ copiedArgSrc -> {
        var copiedArgSrcs = matchOpNamesMappedToCopiedArgumentSources.get(copiedArgSrc.Parameter.Name)
        //The use of AutoMap allows calling "add" on this List without first checking if it is null
        copiedArgSrcs.add(copiedArgSrc)
      })
    })

    copiedTableDefinition.MatchOps.each(\ copiedMatchOp -> {
      var copiedArgSrcs = matchOpNamesMappedToCopiedArgumentSources.get(copiedMatchOp.Name)
      // Use of AutoMap allows calling "each" on this list without first checking if it is null
      copiedArgSrcs.each(\ copiedArgSrc -> copiedMatchOp.addToArgumentSources(copiedArgSrc))
    })

    copiedTableDefinition.TableCode = null
    copiedTableDefinition.TableName = displaykey.Web.Rating.RateTableDefinition.CopyPrefix(this.TableName)

    for (column in copiedTableDefinition.AllColumns) {
      //change all columns to point to the new rate table definition
      column.Definition = copiedTableDefinition
      //change all parameters that depend on another column to point to the columns in the new table definition
      if (column.IsParameterColumn and column.DependsOn != null) {
        column.DependsOn = copiedTableDefinition.SortedParameters.firstWhere(\ p -> p.ColumnName == column.DependsOn.ColumnName)
      }
    }
    return copiedTableDefinition
  }

  function isEqual(other : RateTableDefinition) : boolean {
    if (this.EntityName != other.EntityName) return false
    if (this.PolicyLine != other.PolicyLine) return false
    if (this.TableCode != other.TableCode) return false
    if (this.MatchOps.Count != other.MatchOps.Count) return false
    if (this.Factors.Count != other.Factors.Count) return false

    return sameMatchOpsAs(other) and sameFactorsAs(other)
  }

  private function sameFactorsAs(other : RateTableDefinition) : boolean {
    var same : boolean = true
    this.Factors.eachWithIndex(\ f, i -> {
      if (!f.isEqual(other.Factors[i])) {
        same = false
      }
    })
    return same
  }

  private function sameMatchOpsAs(other : RateTableDefinition) : boolean {
    var same : boolean = true
    this.MatchOps.eachWithIndex(\ op, i -> {
      if (!op.isEqual(other.MatchOps[i])) {
        same = false
      }
    })
    return same
  }

  function getParameterSet() : CalcRoutineParameterSet {
    if (this.ArgumentSourceSets.Count > 0) {
      return this.ArgumentSourceSets.first().CalcRoutineParameterSet
    } else {
      return null
    }
  }

  function setParameterSet(paramSet : CalcRoutineParameterSet) {
    var sets = this.ArgumentSourceSets
    sets.each(\argSrcSet -> {
      this.removeFromArgumentSourceSets(argSrcSet)
    })
    // PC-15668: do we really want to clear out everything here, or should
    // we try to retain anything that could carry over from one param set to another?
    for (op in this.MatchOps) {
      for (argumentSource in op.ArgumentSources) {
        argumentSource.remove()
      }
    }
    var defaultArgSrcSet = new RateTableArgumentSourceSet()
    defaultArgSrcSet.CalcRoutineParameterSet = paramSet
    this.addArgumentSourceSet(defaultArgSrcSet)
  }

  function getArgumentSourceSet(code : String) : RateTableArgumentSourceSet {
    return this.ArgumentSourceSets.firstWhere(\argSrcSet -> argSrcSet.Code == code)
  }

  function addArgumentSourceSet(rtArgumentSourceSet : RateTableArgumentSourceSet) {
    // for now only supports a single RateTableArgumentSourceSet
    if (this.ArgumentSourceSets == null or this.ArgumentSourceSets.IsEmpty) {
      this.addToArgumentSourceSets(rtArgumentSourceSet)
    } else {
      var argSrcSet = this.getArgumentSourceSet(rtArgumentSourceSet.Code)
      if (argSrcSet != null) {
        // remove the current argSrcSet, because we support only one.
        this.removeFromArgumentSourceSets(argSrcSet)
        argSrcSet.remove()
      }
      this.addToArgumentSourceSets(rtArgumentSourceSet)
    }
  }

}
