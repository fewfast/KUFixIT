alter table public."FixList"
  drop constraint if exists fixlist_area_matches_building;

alter table public."FixList"
  add constraint fixlist_area_matches_building
  check (
    (building = 'other' and area is not null)
    or (
      building <> 'other'
      and (area is null or area = building)
    )
  );
