package gw.lob.cp

uses gw.api.domain.CoverableAdapter
uses gw.api.util.JurisdictionMappingUtil
uses gw.policy.PolicyLineConfiguration

uses java.lang.UnsupportedOperationException
uses java.util.ArrayList
uses java.util.Date

@Export
class CPLocationCoverableAdapter implements CoverableAdapter {
  var _owner : CPLocation

  construct(owner : CPLocation) {
    _owner = owner
  }

  override property get PolicyLine() : PolicyLine {
    return _owner.CPLine
  }

  override property get PolicyLocations() : PolicyLocation[] {
    var locs = new ArrayList<PolicyLocation>()
    locs.add(_owner.Location)
    return locs.toTypedArray()
  }

  override property get State() : Jurisdiction {
    return JurisdictionMappingUtil.getJurisdiction(_owner.Location)
  }

  override property get AllCoverages() : Coverage[] {
     return _owner.Coverages
  }

  override function addCoverage( p0: Coverage ) : void {
    _owner.addToCoverages( p0 as CPLocationCov )
  }

  override function removeCoverage( p0: Coverage ) : void {
    _owner.removeFromCoverages( p0 as CPLocationCov )
  }

  override property get AllExclusions() : Exclusion[] {
    return new Exclusion[0]
  }

  override function addExclusion( p0: Exclusion ) : void {
    throw new UnsupportedOperationException(displaykey.CoverableAdapter.Error.ExclusionsNotImplemented)
  }

  override function removeExclusion( p0: Exclusion ) : void {
    throw new UnsupportedOperationException(displaykey.CoverableAdapter.Error.ExclusionsNotImplemented)
  }

  override property get AllConditions() : PolicyCondition[] {
    return new PolicyCondition[0]
  }

  override function addCondition( p0: PolicyCondition ) : void {
    throw new UnsupportedOperationException(displaykey.CoverableAdapter.Error.ConditionsNotImplemented)
  }

  override function removeCondition( p0: PolicyCondition ) : void {
    throw new UnsupportedOperationException(displaykey.CoverableAdapter.Error.ConditionsNotImplemented)
  }

  override property get ReferenceDateInternal() : Date {
    return _owner.ReferenceDateInternal
  }

  override property set ReferenceDateInternal( date : Date ) {
    _owner.ReferenceDateInternal = date
  }

  override property get DefaultCurrency() : Currency {
    //OOTB there are no line level coverages and the currency for the line is not exposed.  skips line in currency inheritance hierarchy
    return _owner.Branch.PreferredCoverageCurrency
  }

  override property get AllowedCurrencies() : List<Currency> {
    return PolicyLineConfiguration.getByLine(InstalledPolicyLine.TC_CP).AllowedCurrencies
  }
}