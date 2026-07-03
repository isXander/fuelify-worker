-- Migration number: 0003
CREATE INDEX stations_h3_r6_closures_idx ON stations (h3_index_r6, temporary_closure, permanent_closure);
