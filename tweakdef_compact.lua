local randomizer_options = {
  ignore_weights = true,
};
Shuffler = {}
Shuffler.__index = Shuffler
function Shuffler:get_tbl_unique_count(tbl)
  local unique = {}
  for i, v in ipairs(tbl) do
    unique[v] = true
  end
  local count = 0
  for k, v in pairs(unique) do
    count = count + 1
  end
  return count
end
function Shuffler:new(tbl)
  local self = setmetatable({}, Shuffler)
  self.tbl = tbl
  self.index = 1
  self.unique_count = self:get_tbl_unique_count(tbl)
  local duplicate = {}
  for i, v in ipairs(tbl) do
    duplicate[i] = v
  end
  self.duplicate = duplicate
  return self
end
function Shuffler:shuffle()
  for i = #self.tbl, 2, -1 do
    local j = math.random(i)
    self.tbl[i], self.tbl[j] = self.tbl[j], self.tbl[i]
  end
  return self.tbl
end
function Shuffler:reset()
  self.index = 1
  local new_tbl = {}
  for i, v in ipairs(self.duplicate) do
    new_tbl[i] = v
  end
  self.tbl = new_tbl
  self:shuffle()
end
function Shuffler:next()
  if #self.tbl == 0 then
    self:reset()
    return self.index
  end

  self.index = (self.index % #self.tbl) + 1
  return self.index
end
function Shuffler:get_current()
  return self.tbl[self.index]
end
function Shuffler:remove_current()
  local elem = self.tbl[self.index]
  table.remove(self.tbl, self.index)
  self.index = self.index - 1
  if self.index < 1 then
    self.index =  #self.tbl
  end
  if #self.tbl == 0 then
    self:reset()
  end
  return elem
end
function Shuffler:find_next_index_with_condition(condition)
  if #self.tbl == 0 then
    self:reset()
  end
  for i = 1, #self.tbl do
    self:next()
    if condition(self.tbl[self.index]) then
      return self.index
    end
  end
  return nil
end
Randomizer = {}
Randomizer.__index = Randomizer
function Randomizer:new(categories, requirements, constructors)
  local self = setmetatable({}, Randomizer)
  self.categories = categories
  self.requirements = requirements
  self.constructors = constructors
  self.reserved = {}
  self.units_by_category = {}
  self.shufflers = {}
  return self
end
function Randomizer:get_category_name(name)
  for category_name, category in pairs(self.categories) do
    if category.category_fn(name) then
      return category_name
    end
  end
  return nil
end
function Randomizer:find_requirements(name)
  for i, req in ipairs(self.requirements) do
    if req.filter(name) then
      return req.reqs
    end
  end
  return nil
end
function Randomizer:init_unit_lists()
  for i, constructor in ipairs(self.constructors) do
    local category_name = self:get_category_name(constructor)
    if category_name then
      if not self.units_by_category[category_name] then
        self.units_by_category[category_name] = {}
      end
      local ud = UnitDefs[constructor]
      if ud and ud.builder and ud.buildoptions then
        for k, v in pairs(ud.buildoptions) do
          table.insert(self.units_by_category[category_name], v)
        end
      end
    end
  end
end
function Randomizer:init_shufflers()
  for category_name, category in pairs(self.categories) do
    if self.units_by_category[category_name] then
      local shuffler = Shuffler:new(self.units_by_category[category_name])
      shuffler:shuffle()
      self.shufflers[category_name] = shuffler
    end
  end
  local reserved_units = {}
  for i, constructor in ipairs(self.constructors) do
    local category_name = self:get_category_name(constructor)
    if category_name then
      local ud = UnitDefs[constructor]
      if ud and ud.builder and ud.buildoptions then
        local reqs = self:find_requirements(constructor)
        if reqs then
          for j, req in ipairs(reqs) do
            local index = self.shufflers[category_name]:find_next_index_with_condition(req.req)
            if index then
              local unit_name = self.shufflers[category_name].tbl[index]
              table.insert(reserved_units, unit_name)
              self.shufflers[category_name]:remove_current()
            end
          end
        end
      end
      self.reserved = reserved_units
      self.shufflers["reserved"] = Shuffler:new(reserved_units)
    end
  end
end
function array_contains(array, value) for i, v in ipairs(array) do if v == value then return true end end return false end
function Randomizer:create_build_options()
  for i, constructor in ipairs(self.constructors) do
    local category_name = self:get_category_name(constructor)
    if category_name then
      local ud = UnitDefs[constructor]
      if ud and ud.builder and ud.buildoptions then
        local build_options_count = #ud.buildoptions
        local new_buildoptions = {}
        local reqs = self:find_requirements(constructor)
        if reqs then
          for i, req in ipairs(reqs) do
            local index = self.shufflers["reserved"]:find_next_index_with_condition(req.req)
            if index then
              local unit_name = self.shufflers["reserved"].tbl[index]
              table.insert(new_buildoptions, unit_name)
              self.shufflers["reserved"]:remove_current()
            end
          end
        end
        local total_weight = nil
        if not randomizer_options.ignore_weights and self.categories[category_name].weights then
          total_weight = 0
          for k, v in pairs(self.categories[category_name].weights) do
            total_weight = total_weight + v
          end
        end
        for i = #new_buildoptions, build_options_count do
          local next_category_name = category_name
          if total_weight then
            local weights = self.categories[category_name].weights
            local r = math.random(total_weight)
            local acc = 0
            for k, v in pairs(weights) do
              acc = acc + v
              if r <= acc then
                next_category_name = k
                break
              end
            end
          end

          local index = self.shufflers[next_category_name]:next()
          local unit_name = self.shufflers[next_category_name].tbl[index]
          if unit_name and not array_contains(new_buildoptions, unit_name) then
            table.insert(new_buildoptions, unit_name)
            self.shufflers[next_category_name]:remove_current()
          else
            i = i - 1
          end
        end
        ud.buildoptions = new_buildoptions
      end
    end
  end
end
local coms = {"armcom","corcom"}
if Spring.GetModOptions().experimentallegionfaction then 
  local leg = {"legcom", "legcomlvl2", "legcomlvl3", "legcomlvl4"}
  for _, v in ipairs(leg) do
    table.insert(coms, v)
  end
end
function get_child_builders(builder, tbl)
  if not tbl[builder] then 
      tbl[builder] = true
  end
  local ud = UnitDefs[builder]
  if ud and ud.builder and ud.buildoptions then
      for i, v in ipairs(ud.buildoptions) do
          local u2 = UnitDefs[v]
          if u2 and u2.builder and not tbl[v] then
              get_child_builders(v, tbl)
          end
      end
  end
end
function get_builders()
  local builders_set = {}
  for i, v in ipairs(coms) do
      get_child_builders(v, builders_set)
  end
  local builders_array = {}
  for k in pairs(builders_set) do
      table.insert(builders_array, k)
  end
  return builders_array
end
local constructors = get_builders()
function is_land_factory(name)
  return name == "armlab"
    or name == "armalab"
    or name == "corlab"
    or name == "coralab"
    or name == "leglab"
    or name == "legalab"
    or name == "armvp"
    or name == "armavp"
    or name == "legvp"
    or name == "legavp"
    or name == "corvp"
    or name == "coravp"
    or name == "armhp"
    or name == "corhp"
end
function is_sea_factory(name)
  return name == "armsy"
    or name == "armasy"
    or name == "corsy"
    or name == "corasy"
    or name == "armfhp"
    or name == "corfhp"
end
function is_air_factory(name)
  return name == "armap"
    or name == "armaap"
    or name == "corap"
    or name == "coraap"
    or name == "legap"
    or name == "legaap"
    or name == "armplat"
    or name == "corplat"
end
function is_amphibious_factory(name)
  return name == "armasub"
    or name == "corasub"
end
function is_experimental_factory(name)
  return name == "armshltx"
    or name == "corgant"
    or name == "leggant"
end
function is_experimental_amphibious_factory(name)
  return name == "armshltxuw"
    or name == "corgantuw"
end
function is_surface_constructor(name)
  local ud = UnitDefs[name]
  if ud and ud.speed and ud.category then
    if (string.find(ud.category, "VTOL") 
    or (string.find(ud.category, "HOVER") and not string.find(ud.category, "NOTHOVER")) 
    or string.find(ud.category, "CANBEUW")) then
      return true
    end
  end
  return false
end
function is_land_constructor(name)
  local ud = UnitDefs[name]
  if ud and ud.speed and ud.category then
    if is_surface_constructor(name) then
      return false
    elseif string.find(ud.category, "BOT") or string.find(ud.category, "TANK") then
      return true
    end
  end
  return false
end
function is_sea_constructor(name)
  local ud = UnitDefs[name]
  if ud and ud.speed then
    -- Constructors
    if is_surface_constructor(name) then
      return false
    elseif is_land_constructor(name) then
      return false
    else
      return true
    end
  end
  return false
end
requirements = {
  {
    filter = function(unit_name)
      local ud = UnitDefs[unit_name]
      if ud and (unit_name == "armcom" or unit_name == "corcom" or unit_name:sub(1, #"legcom") == "legcom") then
        return true
      end
      return false
    end,
    reqs = {
      {
        req = function(unit_name)
          local ud = UnitDefs[unit_name]
          if is_land_factory(unit_name) and ud and ud.metalcost < 1000 then
            return true
          end
          return false
        end,
      },
      {
        req = function(unit_name)
          local ud = UnitDefs[unit_name]
          if is_sea_factory(unit_name) and ud and ud.metalcost < 1000 then
            return true
          end
          return false
        end,
      },
      {
        req = function(unit_name)
          if unit_name == "armmex" or unit_name == "cormex" then
            return true
          end
        end,
      },
      {
        req = function(unit_name)
          if unit_name == "armsolar" or unit_name == "corsolar" then
            return true
          end
        end,
      },
      {
        req = function(unit_name)
          if unit_name == "armtide" or unit_name == "cortide" then
            return true
          end
        end,
      },
      {
        req = function(unit_name)
          if unit_name == "armmoho" or unit_name == "cormoho" then
            return true
          end
        end,
      },
    },
  },
}

-- Category table which will be used to determine which category the builder unit belongs to
local categories = {
  surface_constructors = {
    category_fn = function(name)
      return is_surface_constructor(name)
    end,
  },
  land_constructors = {
    category_fn = function(name)
      return is_land_constructor(name)
    end,
  },
  sea_constructors = {
    category_fn = function(name)
      return is_sea_constructor(name)
    end,
  },
  land_factories = {
    category_fn = function(name)
      return is_land_factory(name)
    end,
  },
  sea_factories = {
    category_fn = function(name)
      return is_sea_factory(name)
    end,
  },
  air_factories = {
    category_fn = function(name)
      return is_air_factory(name)
    end,
  },
  amphibious_factories = {
    category_fn = function(name)
      return is_amphibious_factory(name)
    end,
  },
  experimental_non_amphibious_factories = {
    category_fn = function(name)
      return is_experimental_factory(name)
    end,
  },
  experimental_amphibious_factories = {
    category_fn = function(name)
      return is_experimental_amphibious_factory(name)
    end,
  },
}
local randomizer = Randomizer:new(categories, requirements, constructors)
randomizer:init_unit_lists()
randomizer:init_shufflers()
randomizer:create_build_options()
