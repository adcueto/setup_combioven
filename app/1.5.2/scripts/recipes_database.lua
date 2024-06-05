--[[
Copyright 2021, Pro-Servicios SA de CV.
All Rights Reserved.
Functions for database managment Save/Execute/Delete/Update
For more information email humberto.rodriguez@pro-servicios.com
** Author: Humberto Rodriguez **
]]--
--[[        DATA STRUCTURE OF BUFFER RECIPE BEFORE DOES NEW INSERT ON DATABASE        ]]--
--[[
recipeSelPresets 
[1]         [2]       [3]         [4]           [presets + 1]
P1_name     p1_name   p3_name     p4_name  ...  name
P1_vale     p2_value  p3_value    p4_value      type
                                                presets
                                                steps

recipeSelected
[1]           [2]           [3]       ...       [steps+1]
s1_mode       s2_mode       s2_mode             time_min
s1_humidity   s2_humidity   s2_humidity         time_max
s1_tempmin    s2_tempmin    s3_tempmin          time_target
s1_tempmax    s2_tempmax    s3_tempmax          core_temp
s1_time       s2_time       s3_time
s1_speed      s2_speed      s3_speed

]]--

 ---This is where we do all of the Database interaction and initialization.
 ---we connect, query, storage and update our target database table via the sqlite3 plugin
 
local myenv = gre.env({ "target_os", "target_cpu" })
if(myenv.target_os=="win32")then
  package.cpath = gre.SCRIPT_ROOT .. "\\" .. myenv.target_os .. "-" .. myenv.target_cpu .."\\luasql_sqlite3.dll;" .. package.cpath 
else
  package.cpath = gre.SCRIPT_ROOT .. "/" .. myenv.target_os .. "-" .. myenv.target_cpu .."/luasql_sqlite3.so;" .. package.cpath 
end
luasql = require("luasql_sqlite3")
local database = "recipesdb.sqlite"
local env = assert(luasql.sqlite3())
db = assert(env:connect(gre.SCRIPT_ROOT .. "/"..database, "Failed to connect to database"))
local gFilterActived = 0

tempKey         = {}    -- Temperature key modifier from database
timeKey         = {}    -- Time key modifier from database
coreKey         = {}    -- Core Temp key modifier from database
deltaKey        = {}    -- Delta key modifier from recipe selected
speedKey        = {}    -- Speed Fan key modifier from database
recipes_auto    = {}    -- backup all user recipes in Modo_Programacion
dataFilter      = {}    -- backup of recipes finded by user input text
recipeSelected  = {}    -- backup parameters of complete recipe
recipeSelPresets= {}    -- backup presets of complete recipe selected
gindexStep      = 0     -- Global index step for each recipe
gPreviousIndex  = 0     -- Global previous index for each recipe
totalSteps      = 0     -- Total steps from recipe selected
recipe_id       = 0     -- Recipe ID from database

local function ClearStepTable()
  if(gindexStep ~= 0) then
    for i=1, table.maxn(recipeSelected)+1 do
        recipeSelected[i] = nil
    end
    for i=1, table.maxn(recipeSelPresets)+1 do
        recipeSelPresets[i] = nil
    end
  end
end

---We are only storing names and user IDs locally. Get the data for this particular user
---Get the control data for the user and populate our UI with their values
local function SwitchRecipe_Manual(recipe_id)
  ClearStepTable()
  local statement = string.format("SELECT * from recipes_manual WHERE id=%s",recipe_id)
  local cur = db:execute(statement)
  local row = cur:fetch({}, "a")
 -- query the users control data and set it to the UI
  local data = {}
  data["Layer_AutoHeader2.text_HeaderAuto.text_RecipeName"] = row.name
  data["Layer_AutoSteps.text_HeaderAuto.text_RecipeName"] = row.name
  data["Layer_TopBar.IconMainMenu_Status.mode_status"] = row.type--recipes_auto[recipe_id%100].name
  gre.set_data(data)

  --We create list steps on display with bkg image and icon by type
  totalSteps = row.steps
  gindexStep = 1
  
  gre.set_table_attrs("Layer_ListTableSteps.RecipesAutoSteps",{rows = totalSteps})
  for i=1, totalSteps do
    local dataRecipe={}
    dataRecipe["mode"]      = row[string.format("s%d_mode",i)]
    dataRecipe["humidity"]  = row[string.format("s%d_humidity",i)]
    dataRecipe["tempcam"]   = row[string.format("s%d_tempmax",i)]
    dataRecipe["time"]      = row[string.format("s%d_time",i)]
    dataRecipe["speed"]     = row[string.format("s%d_speed",i)]
    dataRecipe["stepTime"]  = 0
    dataRecipe["stepTcore"] = 0    
    table.insert(recipeSelected,dataRecipe)
  end
  local cookMode = " "
  local metadataRecipe = {}
  metadataRecipe["tDelta"]        = 0
  metadataRecipe["cookmode"]      = cookMode
  table.insert(recipeSelected,metadataRecipe)
end


---We are only storing names and user IDs locally. Get the data for this particular user
---Get the control data for the user and populate our UI with their values
local function SwitchRecipe(recipe_id)
  ClearStepTable()

--  local statement = string.format("SELECT * from recipes_auto where id=%s", recipes_auto[recipe_id].id)
  local statement = string.format("SELECT * from recipes_auto WHERE id=%s",recipe_id)
  local cur = db:execute(statement)
  local row = cur:fetch({}, "a")
 -- query the users control data and set it to the UI
  local data = {}
  data["Layer_AutoHeader2.text_HeaderAuto.text_RecipeName"] = row.name
  data["Layer_AutoSteps.text_HeaderAuto.text_RecipeName"] = row.name
  data["Layer_TopBar.IconMainMenu_Status.mode_status"] = row.type--recipes_auto[recipe_id%100].name
  gre.set_data(data)
  
  --We create list of presets on display with icon image and slider color 
  local txtparam
  local cookMode 
  local setparam = {}
  data["Layer_AutoSteps.icon_CircleFunct.imgMode"] = "images/icon_timeStep.png"
  for i=1, 4 do
    local dataRecipe = {}
    if (i <= row.presets) then
      txtparam = row[string.format("p%d_name",i)] 
      --print( "pname: "..txtparam)
      data[string.format("Layer_Recipe.Slider_%d.Slider_IconBtn.pimg",i)]  = string.format("images/icon_%s.png", txtparam)
      dataRecipe["name"]  = txtparam
      dataRecipe["value"] = row[string.format("p%d_value",i)]
      table.insert(recipeSelPresets,dataRecipe)
      -- Verify each preset to find keys and draw slider
      if(txtparam == "Size") then
        data[string.format("Layer_Recipe.Slider_%d.Slider_Text.pname",i)]  = "Tamaño"--txtparam
        timeKey.val = row[string.format("p%d_value",i)]
        timeKey.id  = i
        
      elseif(txtparam == "CookTime") then
        data[string.format("Layer_Recipe.Slider_%d.Slider_Text.pname",i)]  = "Velocidad de cocción"--txtparam
        data[string.format("Layer_Recipe.Slider_%d.Slider_Data_Text.alpha",i)]  = 255
        data[string.format("Layer_Recipe.Slider_%d.Slider_Ball.slider_alpha",i)] = 255
        data[string.format("Layer_Recipe.Slider_%d.Slider_Color.img",i)]   = "images/ColorSlider_Gray_Full.png"
        data[string.format("Layer_Recipe.Slider_%d.Slider_Shadow.img",i)]  = "images/ShadowSlider_Full.png"
        timeKey.val = row[string.format("p%d_value",i)]
        timeKey.id  = i
        cookMode    = "cookTime"
        
      elseif(txtparam == "Thickness") then
        data[string.format("Layer_Recipe.Slider_%d.Slider_Text.pname",i)] = "Espesor"--txtparam
        data[string.format("Layer_Recipe.Slider_%d.Slider_Data_Text.alpha",i)]  = 0
        data[string.format("Layer_Recipe.Slider_%d.Slider_Ball.slider_alpha",i)] = 0
        data[string.format("Layer_Recipe.Slider_%d.Slider_Color.img",i)]  = "images/ColorSlider_Gray_4Seg.png"
        data[string.format("Layer_Recipe.Slider_%d.Slider_Shadow.img",i)] = "images/ShadowSlider_4Seg.png"
                
      elseif (txtparam == "Browning") then
        data[string.format("Layer_Recipe.Slider_%d.Slider_Text.pname",i)] = "Dorado"--txtparam
        data[string.format("Layer_Recipe.Slider_%d.Slider_Data_Text.alpha",i)]  = 0
        data[string.format("Layer_Recipe.Slider_%d.Slider_Ball.slider_alpha",i)] = 0
        data[string.format("Layer_Recipe.Slider_%d.Slider_Color.img",i)]  = "images/ColorSlider_Gray_4Seg.png"
        data[string.format("Layer_Recipe.Slider_%d.Slider_Shadow.img",i)] = "images/ShadowSlider_4Seg.png"
        tempKey.val = row[string.format("p%d_value",i)]
        tempKey.id  = i

      elseif (txtparam == "CoreProbe") then
        data[string.format("Layer_Recipe.Slider_%d.Slider_Text.pname",i)] = "Temperatura interna"--txtparam
        data[string.format("Layer_Recipe.Slider_%d.Slider_Data_Text.alpha",i)]  = 255
        data[string.format("Layer_Recipe.Slider_%d.Slider_Ball.slider_alpha",i)] = 255
        data[string.format("Layer_Recipe.Slider_%d.Slider_Color.img",i)]  = "images/ColorSlider_Gray_Full.png"
        data[string.format("Layer_Recipe.Slider_%d.Slider_Shadow.img",i)] = "images/ShadowSlider_Full.png"
        data["Layer_AutoSteps.icon_CircleFunct.imgMode"] = "images/icon_coreStep.png"
        coreKey.val = row[string.format("p%d_value",i)]
        coreKey.id  = i
        cookMode    = "coreProbe"
        
      elseif (txtparam == "Gratin") then
        data[string.format("Layer_Recipe.Slider_%d.Slider_Text.pname",i)]  = "Gratinado"--txtparam
       tempKey.val = row[string.format("p%d_value",i)]
       tempKey.id  = i
        
      elseif (txtparam == "FanSpeed") then
        data[string.format("Layer_Recipe.Slider_%d.Slider_Text.pname",i)]  = "Velocidad del aire"--txtparam
        data[string.format("Layer_Recipe.Slider_%d.Slider_Data_Text.alpha",i)]  = 0
        data[string.format("Layer_Recipe.Slider_%d.Slider_Ball.slider_alpha",i)]  = 0
        data[string.format("Layer_Recipe.Slider_%d.Slider_Color.img",i)]  = "images/ColorSlider_Gray_4Seg.png"
        data[string.format("Layer_Recipe.Slider_%d.Slider_Shadow.img",i)] = "images/ShadowSlider_4Seg.png"   
        speedKey.val = row[string.format("p%d_value",i)]
        speedKey.id  = i 

      elseif (txtparam == "TempSealed") then
        data[string.format("Layer_Recipe.Slider_%d.Slider_Text.pname",i)]  = "Temp. sellado"--txtparam
        tempKey.val = row[string.format("p%d_value",i)]
        tempKey.id  = i
        
      elseif (txtparam == "TempOven") then
        data[string.format("Layer_Recipe.Slider_%d.Slider_Text.pname",i)]  = "Temp. del horno"--txtparam
        data[string.format("Layer_Recipe.Slider_%d.Slider_Data_Text.alpha",i)]  = 0
        data[string.format("Layer_Recipe.Slider_%d.Slider_Ball.slider_alpha",i)] = 0
        data[string.format("Layer_Recipe.Slider_%d.Slider_Color.img",i)]  = "images/ColorSlider_Gray_4Seg.png"
        data[string.format("Layer_Recipe.Slider_%d.Slider_Shadow.img",i)] = "images/ShadowSlider_4Seg.png"
        tempKey.val = row[string.format("p%d_value",i)]
        tempKey.id  = i
        
      elseif (txtparam == "Delta") then
        data[string.format("Layer_Recipe.Slider_%d.Slider_Text.pname",i)]  = "Delta-T"--txtparam
        data[string.format("Layer_Recipe.Slider_%d.Slider_Data_Text.alpha",i)]  = 255
        data[string.format("Layer_Recipe.Slider_%d.Slider_Ball.slider_alpha",i)] = 255
        data[string.format("Layer_Recipe.Slider_%d.Slider_Color.img",i)]  = "images/ColorSlider_Gray_Full.png"
        data[string.format("Layer_Recipe.Slider_%d.Slider_Shadow.img",i)] = "images/ShadowSlider_Full.png"
        tempKey.val = row[string.format("p%d_value",i)]
        tempKey.id  = i
        data[string.format("Layer_Recipe.Slider_%d.Slider_Data_Text.data",tempKey.id)] = string.format("%d °C",tempKey.val)
        cookMode    = "coreDelta"
      
      elseif(txtparam == "Humidity") then
        data[string.format("Layer_Recipe.Slider_%d.Slider_Text.pname",i)] = "Humidificación"--txtparam
        data[string.format("Layer_Recipe.Slider_%d.Slider_Data_Text.alpha",i)]  = 0
        data[string.format("Layer_Recipe.Slider_%d.Slider_Ball.slider_alpha",i)] = 0
        data[string.format("Layer_Recipe.Slider_%d.Slider_Color.img",i)]  = "images/ColorSlider_Gray_4Seg.png"
        data[string.format("Layer_Recipe.Slider_%d.Slider_Shadow.img",i)] = "images/ShadowSlider_4Seg.png"
      
      elseif(txtparam == "Fluffing") then
        data[string.format("Layer_Recipe.Slider_%d.Slider_Text.pname",i)] = "Fermentación"--txtparam
        data[string.format("Layer_Recipe.Slider_%d.Slider_Data_Text.alpha",i)]  = 0
        data[string.format("Layer_Recipe.Slider_%d.Slider_Ball.slider_alpha",i)] = 0
        data[string.format("Layer_Recipe.Slider_%d.Slider_Color.img",i)]  = "images/ColorSlider_Gray_4Seg.png"
        data[string.format("Layer_Recipe.Slider_%d.Slider_Shadow.img",i)] = "images/ShadowSlider_4Seg.png"
      end
     
      setparam["hidden"] = 0
      gre.set_group_attrs(string.format("Layer_Recipe.Slider_%d",i), setparam)
      SetBarRecipeSlider(row[string.format("p%d_value",i)],i)
    else
      setparam["hidden"] = 1
      gre.set_group_attrs(string.format("Layer_Recipe.Slider_%d",i), setparam)
    end
  end
  gre.set_data(data)
  

  --We make a backup data of type and presets number
  local dataPresets={}
  dataPresets["name"]     = row.name
  dataPresets["type"]     = row.type
  dataPresets["subtype"]  = row.subtype
  dataPresets["presets"]  = row.presets
  dataPresets["steps"]    = row.steps
  table.insert(recipeSelPresets,dataPresets)
  dataPresets=nil

  --We create list steps on display with bkg image and icon by type
  totalSteps = row.steps
  gindexStep = 1
  
  local totalTime=0
  gre.set_table_attrs("Layer_ListTableSteps.RecipesAutoSteps",{rows = totalSteps})
  for i=1, totalSteps do
    local dataRecipe={}
    dataRecipe["mode"]      = row[string.format("s%d_mode",i)]
    dataRecipe["humidity"]  = row[string.format("s%d_humidity",i)]
    dataRecipe["tempmin"]   = row[string.format("s%d_tempmin",i)]
    dataRecipe["tempmax"]   = row[string.format("s%d_tempmax",i)]
    dataRecipe["time"]      = row[string.format("s%d_time",i)]
    dataRecipe["speed"]     = row[string.format("s%d_speed",i)]
    dataRecipe["tempcam"]   = 0
    dataRecipe["stepTime"]  = 0
    dataRecipe["stepTcore"] = 0
    table.insert(recipeSelected,dataRecipe)
  end
  
  
  
  --Set time text on parameters for user--
  local metadataRecipe={}
  metadataRecipe["time_min"]      = row.time_min
  metadataRecipe["time_max"]      = row.time_max
  metadataRecipe["time_target"]   = row.time_target
  metadataRecipe["tcore_target"]  = row.core_temp
  metadataRecipe["tcore_amount"]  = 0
  metadataRecipe["tDelta"]        = 0
  metadataRecipe["cookmode"]      = cookMode
  table.insert(recipeSelected,metadataRecipe)
  --prueba
  print("tcore_target", row.core_temp)
  
  --Always starts with time but it changes coreProbe when you press tickness > 50% 
  --We have only 3 CookMode options:  1=CoreProbe, 2=CookTime, 3=CoreDelta 
  if(cookMode == "coreProbe") then  --if(row.core_temp ~= 0) then
    data[string.format("Layer_Recipe.Slider_%d.Slider_Data_Text.data",coreKey.id)] = string.format("%d °C",row.core_temp)

  elseif(cookMode == "cookTime") then
    data[string.format("Layer_Recipe.Slider_%d.Slider_Data_Text.data",timeKey.id)] = string.format("%.2d:%.2d",recipeSelected[totalSteps+1].time_target/60,recipeSelected[totalSteps+1].time_target%60) 
  
  elseif(cookMode == "coreDelta") then
    data[string.format("Layer_Recipe.Slider_%d.Slider_Data_Text.data",coreKey.id)] = string.format("%d °C",row.core_temp)
    recipeSelected[totalSteps+1].tDelta  = tempKey.val
  end
  gre.set_data(data)
end


function CalcTempStatusCircle(newTemperature)
  local new_angle = math.ceil((newTemperature * 360) / 300)
  if (new_angle == nil ) then
  new_angle=0
  end
  gre.set_value("Layer_AutoSteps.icon_CircleProgress.angleTime",new_angle-268) --92 angleTimeBall+98
  gre.set_value("Layer_AutoSteps.icon_CercleBall.angleTime",new_angle-170) --190
end

--Shows the recipe steps added from Manual creation
function CBDisplayRecipeSteps_Manual()
  local data = {}
  --local deltaTemp 
  local temperatCam 
  local humidityCam 
  local userAction = 0
  
  for i=1, totalSteps do 
        data["Layer_ListTableSteps.RecipesAutoSteps.img."..i..".1"] = 'images/bar_list_step.png' 
        data["Layer_ListTableSteps.RecipesAutoSteps.bkg."..i..".1"] = 0 --'images/bar_list_step.png'   
        userAction = 0
        
        if(recipeSelected[i].mode == "convection") then
          data["Layer_ListTableSteps.RecipesAutoSteps.mode."..i..".1"]  = "images/recipe_shots/icon_conve_small.png"
          temperatCam = recipeSelected[i].tempcam
          humidityCam = string.format("%d%%", recipeSelected[i].humidity )
      
        elseif(recipeSelected[i].mode == "combined") then
          data["Layer_ListTableSteps.RecipesAutoSteps.mode."..i..".1"]  = "images/recipe_shots/icon_combi_small.png"
          temperatCam = recipeSelected[i].tempcam
          humidityCam = string.format("%d%%", recipeSelected[i].humidity )

        elseif(recipeSelected[i].mode == "steam") then
          data["Layer_ListTableSteps.RecipesAutoSteps.mode."..i..".1"]  = "images/recipe_shots/icon_steam_small.png"
          temperatCam = recipeSelected[i].tempcam
          humidityCam = string.format("%d%%", recipeSelected[i].humidity)
  
        elseif(recipeSelected[i].mode == "load") then
          data["Layer_ListTableSteps.RecipesAutoSteps.mode."..i..".1"]  = "images/recipe_shots/icon_cargar_small.png" 
          data["Layer_ListTableSteps.RecipesAutoSteps.txt."..i..".1"]   = string.format("  %d        Cargar    ",i)   
          data["Layer_ListTableSteps.RecipesAutoSteps.time."..i..".1"]  = string.format("      ")
          userAction = 1
          
        elseif(recipeSelected[i].mode == "hold") then
          data["Layer_ListTableSteps.RecipesAutoSteps.mode."..i..".1"]  = "images/recipe_shots/icon_hold_small.png"
          data["Layer_ListTableSteps.RecipesAutoSteps.txt."..i..".1"]   = string.format("  %d        Mantener    ",i)   
          data["Layer_ListTableSteps.RecipesAutoSteps.time."..i..".1"]  = string.format("      ")
          userAction = 1
          
        elseif(recipeSelected[i].mode == "addliquid") then
          data["Layer_ListTableSteps.RecipesAutoSteps.mode."..i..".1"]  = "images/recipe_shots/add_liquid_small.png" 
          data["Layer_ListTableSteps.RecipesAutoSteps.txt."..i..".1"]   = string.format("  %d         Añadir líquido    ",i)  
          data["Layer_ListTableSteps.RecipesAutoSteps.time."..i..".1"]  = string.format("      ")
          userAction = 1
          
        elseif(recipeSelected[i].mode == "addingredient") then
          data["Layer_ListTableSteps.RecipesAutoSteps.mode."..i..".1"]  = "images/recipe_shots/add_liquid_small.png" 
          data["Layer_ListTableSteps.RecipesAutoSteps.txt."..i..".1"]   = string.format("  %d         Añadir ingrediente",i)  
          data["Layer_ListTableSteps.RecipesAutoSteps.time."..i..".1"]  = string.format("      ")
          userAction = 1
        
        elseif(recipeSelected[i].mode == "brush") then
          data["Layer_ListTableSteps.RecipesAutoSteps.mode."..i..".1"]  = "images/recipe_shots/brush_small.png" 
          data["Layer_ListTableSteps.RecipesAutoSteps.txt."..i..".1"]   = string.format("  %d         Pincelar          ",i)  
          data["Layer_ListTableSteps.RecipesAutoSteps.time."..i..".1"]  = string.format("      ")
          userAction = 1
        
        elseif(recipeSelected[i].mode == "carve") then
          data["Layer_ListTableSteps.RecipesAutoSteps.mode."..i..".1"]  = "images/recipe_shots/cut_small.png" 
          data["Layer_ListTableSteps.RecipesAutoSteps.txt."..i..".1"]   = string.format("  %d         Realizar cortes   ",i)  
          data["Layer_ListTableSteps.RecipesAutoSteps.time."..i..".1"]  = string.format("      ")
          userAction = 1
        end              
 
        local stepTime = recipeSelected[i].time 
        recipeSelected[i].stepTime = stepTime
  
        if (stepTime == 0 and userAction == 0) then
          data["Layer_ListTableSteps.RecipesAutoSteps.txt."..i..".1"] = string.format("  %d        %d°C          %s",i, temperatCam, humidityCam)  
          data["Layer_ListTableSteps.RecipesAutoSteps.time."..i..".1"] = string.format(" Precal.")     
        
        elseif(stepTime ~= 0  and userAction ==0) then
          recipeSelected[totalSteps+1].cookmode = "cookTime"
          local hrs_row  =  stepTime / 60
          local mins_row =  stepTime % 60
          data["Layer_ListTableSteps.RecipesAutoSteps.txt."..i..".1"] = string.format("  %d        %d°C          %s",i, temperatCam, humidityCam)
          data["Layer_ListTableSteps.RecipesAutoSteps.time."..i..".1"] = string.format("%.2d:%.2d", hrs_row,mins_row)   
        end
  end
  gre.set_data(data)
  local btn_data = {}
  btn_data["hidden"] = 1
  gre.set_control_attrs("Layer_AutoSteps.icon_gotoAdjust", btn_data)
  gre.set_control_attrs("Layer_AutoSteps.bkg_gotoAdjust", btn_data)
end


--Shows the recipe steps added from Intelligent creation
function CBDisplayRecipeSteps_Intelligent()
  local data = {}
  local deltaTemp 
  local temperatCam 
  local humidityCam 
  local userAction = 0
  
  recipeSelected[totalSteps+1].tcore_amount = 0   --Total core Temperature
  for i=1, totalSteps do 
        data["Layer_ListTableSteps.RecipesAutoSteps.img."..i..".1"] = 'images/bar_list_step.png' 
        data["Layer_ListTableSteps.RecipesAutoSteps.bkg."..i..".1"] = 0 --'images/bar_list_step.png'   
        userAction = 0
 --===================================================================================================
 --Temperature inside oven from cooking type each step Convection/Steam/Combined/Load/Hold/AddLiquid--
 --===================================================================================================
         
        if(recipeSelected[i].mode == "convection") then
          data["Layer_ListTableSteps.RecipesAutoSteps.mode."..i..".1"]  = "images/recipe_shots/icon_conve_small.png"
          deltaTemp = ( recipeSelected[i].tempmax - recipeSelected[i].tempmin) * (tempKey.val) 
          recipeSelected[i].tempcam = recipeSelected[i].tempmin + (deltaTemp/100)
          temperatCam = recipeSelected[i].tempcam
          humidityCam = string.format("%d%%", recipeSelected[i].humidity )
      
        elseif(recipeSelected[i].mode == "combined") then
          data["Layer_ListTableSteps.RecipesAutoSteps.mode."..i..".1"]  = "images/recipe_shots/icon_combi_small.png"
          deltaTemp = ( recipeSelected[i].tempmax - recipeSelected[i].tempmin) * (tempKey.val)
          recipeSelected[i].tempcam = recipeSelected[i].tempmin + (deltaTemp/100)
          temperatCam = recipeSelected[i].tempcam
          humidityCam = string.format("%d%%", recipeSelected[i].humidity)

        elseif(recipeSelected[i].mode == "steam") then
          data["Layer_ListTableSteps.RecipesAutoSteps.mode."..i..".1"]  = "images/recipe_shots/icon_steam_small.png"
          deltaTemp = ( recipeSelected[i].tempmax - recipeSelected[i].tempmin ) * (tempKey.val )
          recipeSelected[i].tempcam = recipeSelected[i].tempmin + (deltaTemp/100)
          temperatCam = recipeSelected[i].tempcam
          humidityCam = string.format("%d%%", recipeSelected[i].humidity)
  
        elseif(recipeSelected[i].mode == "load") then
          data["Layer_ListTableSteps.RecipesAutoSteps.mode."..i..".1"]  = "images/recipe_shots/icon_cargar_small.png" 
          data["Layer_ListTableSteps.RecipesAutoSteps.txt."..i..".1"]   = string.format("  %d        Cargar    ",i)   
          data["Layer_ListTableSteps.RecipesAutoSteps.time."..i..".1"]  = string.format("      ")
          userAction = 1
          
        elseif(recipeSelected[i].mode == "hold") then
          data["Layer_ListTableSteps.RecipesAutoSteps.mode."..i..".1"]  = "images/recipe_shots/icon_hold_small.png"
          data["Layer_ListTableSteps.RecipesAutoSteps.txt."..i..".1"]   = string.format("  %d        Mantener    ",i)   
          data["Layer_ListTableSteps.RecipesAutoSteps.time."..i..".1"]  = string.format("      ")
          userAction = 1
          
        else
          data["Layer_ListTableSteps.RecipesAutoSteps.mode."..i..".1"]  = "images/recipe_shots/add_liquid_small.png" 
          data["Layer_ListTableSteps.RecipesAutoSteps.txt."..i..".1"]   = string.format("  %d         Añadir líquido    ",i)  
          data["Layer_ListTableSteps.RecipesAutoSteps.time."..i..".1"]  = string.format("      ")
          userAction = 1   
        end              
 
        --prueba
        --print("temperatCam",temperatCam)
        --print("humidityCam",humidityCam)
   
   
  --===================================================================================================
 --Check Time cooking each step Convection/Steam/Combined/Load/Hold/AddLiquid--------------------------
 --====================================================================================================
        local stepTime = ( recipeSelected[i].time * recipeSelected[totalSteps+1].time_target ) / 100 -- 100-> 100% complete time 
        recipeSelected[i].stepTime = stepTime

        if (stepTime == 0 and userAction == 0) then
          data["Layer_ListTableSteps.RecipesAutoSteps.txt."..i..".1"] = string.format("  %d        %d°C          %s",i, temperatCam, humidityCam)  
          data["Layer_ListTableSteps.RecipesAutoSteps.time."..i..".1"] = string.format(" Precal.")     
          data["Layer_AutoSteps.text_HeaderAutoGroup.text_HeaderTime.time"] = "Tiempo"
          
        elseif(stepTime ~= 0  and userAction ==0) then
          print("cookmode:",recipeSelected[totalSteps+1].cookmode)
          
          if(recipeSelected[totalSteps+1].cookmode == "cookTime") then
            local hrs_row  =  stepTime / 60
            local mins_row =  stepTime % 60
            data["Layer_ListTableSteps.RecipesAutoSteps.txt."..i..".1"] = string.format("  %d        %d°C          %s",i, temperatCam, humidityCam)
            data["Layer_ListTableSteps.RecipesAutoSteps.time."..i..".1"] = string.format("%.2d:%.2d", hrs_row,mins_row)   

          elseif(recipeSelected[totalSteps+1].cookmode == "coreProbe" or recipeSelected[totalSteps+1].cookmode == "coreDelta")then
            local stepTempCore = math.ceil((recipeSelected[i].time * recipeSelected[totalSteps+1].tcore_target ) / 100)
            recipeSelected[totalSteps+1].tcore_amount = recipeSelected[totalSteps+1].tcore_amount + stepTempCore
            if(recipeSelected[totalSteps+1].tcore_amount>recipeSelected[totalSteps+1].tcore_target)then
               recipeSelected[totalSteps+1].tcore_amount=recipeSelected[totalSteps+1].tcore_target
               print("coreProbe")
            end    
   
            recipeSelected[i].stepTcore = recipeSelected[totalSteps+1].tcore_amount
                -- 
            data["Layer_AutoSteps.text_HeaderAutoGroup.text_HeaderTime.time"] = "Interna"
            data["Layer_ListTableSteps.RecipesAutoSteps.txt."..i..".1"] = string.format("  %d        %d°C          %s",i, temperatCam, humidityCam)
            data["Layer_ListTableSteps.RecipesAutoSteps.time."..i..".1"] = string.format("%d°C", recipeSelected[i].stepTcore)

          end       
        end
  end
  gre.set_data(data)
  local btn_data = {} 
  btn_data["hidden"] = 0
  gre.set_control_attrs("Layer_AutoSteps.icon_gotoAdjust", btn_data)
  gre.set_control_attrs("Layer_AutoSteps.bkg_gotoAdjust", btn_data)
end


-- Se envia el modo de seleccion al backend(Microcontrolador UART3)
function CBSendRecipeStep()
  local typeStep  =0  --[[0: Wait_User action / 1: Preheat/Cooling / 2: Time / 3: coreTemp / 4: Delta-T / 5: Hold]]--
  local data = {}
  local modeSelect  = recipeSelected[gindexStep].mode
  
  if(modeSelect == "load" or modeSelect == "addliquid" or modeSelect == "addingredient" or modeSelect == "brush" or modeSelect == "carve")then
    typeStep = 0        --WAIT FOR USER STEP TYPE
    CBUpdateRecipeInfo(totalSteps,gindexStep,typeStep)
    gre.send_event ("mode_load", gBackendChannel)
    Wait(5)
    data["Layer_AutoSteps.icon_CircleMode.img"]  = string.format("images/icon_step_%s.png",modeSelect)
    data["Layer_AutoSteps.text_CircleTime.data"] = string.format("Cargar")
    gre.set_data(data)
       
  elseif(modeSelect == "hold")then
    typeStep  = 5
    CBUpdateRecipeInfo(totalSteps,gindexStep,typeStep)
    gre.send_event ("mode_hold", gBackendChannel)
    Wait(2)
    data["Layer_AutoSteps.icon_CircleMode.img"] = string.format("images/icon_step_%s.png",modeSelect)
    local tempStep = 70 --recipeSelected[gindexStep].tempcam
    CBUpdateTemperature (tempStep)
    CalcTempStatusCircle(tempStep)
    gre.set_value("Layer_AutoSteps.text_CircleTemp.data", string.format("%d°C",tempStep))
    data["Layer_AutoSteps.text_CircleTime.data"] = string.format("Loop")
    gre.set_data(data)
    Wait(5)
    
  else
    local timeStep    = recipeSelected[gindexStep].stepTime
    local tcoreStep   = recipeSelected[gindexStep].stepTcore
    local tdeltaStep  = recipeSelected[totalSteps+1].tDelta

    if(timeStep == 0 and tcoreStep ==0 and tdeltaStep == 0) then
      typeStep = 1
      gre.set_value("Layer_AutoSteps.text_CircleTime.data", string.format("Precal.")) 
    
    else
      if(recipeSelected[totalSteps+1].cookmode == "coreProbe") then
        typeStep = 3
        CBUpdateTemperProbe(tcoreStep)
        gre.set_value("Layer_AutoSteps.text_CircleTime.data", string.format("%d°C",tcoreStep))
        Wait(2)
    
      elseif(recipeSelected[totalSteps+1].cookmode == "coreDelta") then
        typeStep = 4
        CBUpdateTemperDelta(tdeltaStep)
        Wait(2)
        CBUpdateTemperProbe(tcoreStep)
        gre.set_value("Layer_AutoSteps.text_CircleTime.data", string.format("%d°C",tcoreStep))
        Wait(2)
    
      elseif(recipeSelected[totalSteps+1].cookmode == "cookTime") then
        gre.set_value("Layer_AutoSteps.text_CircleTime.data", string.format("%.2d:%.2d",timeStep/60,timeStep%60))
        typeStep = 2
        CBUpdateTime(timeStep, 0)
        Wait(2)
      end
    end 
    
    CBUpdateRecipeInfo(totalSteps,gindexStep,typeStep)
    Wait(2)
    gre.send_event ("mode_"..modeSelect, gBackendChannel)
    gCombiOvenMode = modeSelect
    Wait(2)
    data["Layer_AutoSteps.icon_CircleMode.img"] = string.format("images/icon_step_%s.png",modeSelect)
    gre.set_data(data)
    
    
    local steamStep = recipeSelected[gindexStep].humidity
    CBUpdateSteam (steamStep)
    gre.set_value("Layer_AutoSteps.text_CircleSteam.data",string.format("%d%%",steamStep))
    Wait(2)
    
    local tempStep = recipeSelected[gindexStep].tempcam
    CBUpdateTemperature (tempStep)
    if(typeStep == 2 or typeStep == 3 or typeStep == 4) then
      CalcTempStatusCircle(tempStep)
    elseif(typeStep == 5) then
      gre.set_value("Layer_AutoSteps.text_CircleTemp.data", string.format("Loop"))
    else
      gre.set_value("Layer_AutoSteps.text_CircleTemp.data", string.format("%d°C",tempStep))
    end
    Wait(2)
    
    local speedStep = recipeSelected[gindexStep].speed
    CBUpdateFanSpeed(speedStep)
    Wait(2)
  end

  if(gPreviousIndex ~=0 or gPreviousIndex ~= nil) then
    data["Layer_ListTableSteps.RecipesAutoSteps.bkg."..gPreviousIndex..".1"] = 0 --'images/bar_list_step.png'
  end
  data["Layer_ListTableSteps.RecipesAutoSteps.bkg."..gindexStep..".1"] = 255--'images/bar_liststep_highlight.png'
  gre.set_data(data)
  gPreviousIndex = gindexStep 
end



---Pull the currently shown Data from the screen and update the database
--from Cooking Parameters Keys
function SaveCurrentPreset(slider_num, slider_val)
  if(tempKey.id == slider_num) then
     tempKey.val = slider_val
  elseif(timeKey.id == slider_num) then
     timeKey.val = slider_val  
  end 
  local statement = string.format("UPDATE recipes_auto SET p%d_value = %d WHERE `id` = %s;", slider_num, slider_val, recipe_id)
  local update = db:execute(statement)
end


function Wait(milisecs)
  for i=milisecs,1000000 do
  end
end


local function ClearTable()
  for i=1, table.maxn(recipes_auto) do
      recipes_auto[i] = nil
  end
end


---Load the initial list of All Programed Recipes stored in Database equipment
-- and create  RecipesListTable with id, name and type
function CBLoadListAllRecipes(mapargs) 
  ClearTable()
  ---Execute Statement for Intelligent Recipes from database
  local cur = db:execute(string.format("SELECT id,name,type,subtype FROM recipes_auto"))
  local row = cur:fetch ({}, "a")
  -- Iterate through the results and populate the lua table
  while row do 
    local data={}
    data["name"]    = row.name
    data["id"]      = row.id
    data["type"]    = row.type
    data["subtype"] = row.subtype
    table.insert(recipes_auto,data)
    --We're done with this row of data so switch with the next
    row = cur:fetch({}, "a")
  end
  
  cur = nil
  row = nil
  ---Execute Statement for Manual Recipes from database
  cur = db:execute(string.format("SELECT id,name,type FROM recipes_manual"))
  row = cur:fetch ({}, "a")
  -- Iterate through the results and populate the lua table
  while row do 
    local data={}
    data["name"] = row.name
    data["id"]   = row.id
    data["type"] = row.type
    table.insert(recipes_auto,data)
    --We're done with this row of data so switch with the next
    row = cur:fetch({}, "a")
  end
  
  cur = nil
  row = nil
  ---Execute Statement for Manual Recipes from database
  cur = db:execute(string.format("SELECT id,name,type FROM recipes_multilevel"))
  row = cur:fetch ({}, "a")
  -- Iterate through the results and populate the lua table
  while row do 
    local data={}
    data["name"] = row.name
    data["id"]   = row.id
    data["type"] = row.type
    table.insert(recipes_auto,data)
    --We're done with this row of data so switch with the next
    row = cur:fetch({}, "a")
  end
  
  
  table.sort(recipes_auto, function(e1, e2) return e1.name < e2.name end )
  local data={}
  --We create list on display with bkg image and icon by type
  for i=1, table.maxn(recipes_auto) do
        data["Layer_ListTable.RecipesListTable.txt."..i..".1"] = recipes_auto[i].name --.." "..recipes_auto[i].type
        data["Layer_ListTable.RecipesListTable.img."..i..".1"] = 'images/bar_list_recipes.png'
        
        if (recipes_auto[i].type == "Intelligent") then
          if (recipes_auto[i].subtype == "Aves") then
            data["Layer_ListTable.RecipesListTable.type."..i..".1"] = "images/recipe_shots/icon_AvesSmall.png"
          elseif(recipes_auto[i].subtype == "Carne") then
            data["Layer_ListTable.RecipesListTable.type."..i..".1"] = "images/recipe_shots/icon_CarneSmall.png"
          elseif(recipes_auto[i].subtype == "Guarniciones") then
            data["Layer_ListTable.RecipesListTable.type."..i..".1"] = "images/recipe_shots/icon_GuarniSmall.png"
          elseif(recipes_auto[i].subtype == "Huevo") then
            data["Layer_ListTable.RecipesListTable.type."..i..".1"] = "images/recipe_shots/icon_HuevoSmall.png"
          elseif(recipes_auto[i].subtype == "Panaderia") then
            data["Layer_ListTable.RecipesListTable.type."..i..".1"] = "images/recipe_shots/icon_PanaderiaSmall.png"
          elseif(recipes_auto[i].subtype == "Pescado") then
            data["Layer_ListTable.RecipesListTable.type."..i..".1"] = "images/recipe_shots/icon_PescadoSmall.png"
          elseif(recipes_auto[i].subtype == "Reheat") then
            data["Layer_ListTable.RecipesListTable.type."..i..".1"] = "images/recipe_shots/icon_ReheatSmall.png"
          elseif(recipes_auto[i].subtype == "Grill") then
            data["Layer_ListTable.RecipesListTable.type."..i..".1"] = "images/recipe_shots/icon_GrillSmall.png"
          end
          
        elseif (recipes_auto[i].type == "Manual") then
          data["Layer_ListTable.RecipesListTable.type."..i..".1"] = "images/recipe_shots/icon_combi_small.png" 
        
        elseif (recipes_auto[i].type == "Multilevel") then
          data["Layer_ListTable.RecipesListTable.type."..i..".1"] = "images/recipe_shots/icon_MLSmall.png"
       
        end
  end
  gre.set_data(data)  
  data = {}
  data["rows"] = table.maxn(recipes_auto) 
  if (data["rows"] == 0) then
     data["hidden"] = 1
  else
     data["hidden"] = 0
  end
  gre.set_table_attrs("Layer_ListTable.RecipesListTable", data)
end



--- On init we pull all recipes down to a local table so we don't have to keep querying the Database.
--- For large databases this is not a good idea. Notice that this is only the usernames and IDs.
function CBInitTable(mapargs) 
  ClearTable()
  local recipe_type = gre.get_value(mapargs.context_control..".recipe_type")
  local cur = db:execute(string.format("SELECT id,name FROM recipes_auto WHERE type='%s'",recipe_type))
  local row = cur:fetch ({}, "a")
  -- Iterate through the results and populate the lua table
  while row do 
    local data={}
    data["name"] = row.name
    data["id"]=row.id
    table.insert(recipes_auto,data)
    --We're done with this row of data so switch with the next
    row = cur:fetch({}, "a")
  end
end




local function SaveAutomaticRecipe(mapargs)
  local rowpresets = table.maxn(recipeSelPresets)
  local rowparamts = table.maxn(recipeSelected)
  
  recipeSelPresets[rowpresets].name = gre.get_value(SAVE_NEW_RECIPE)
  local statement = string.format("INSERT INTO recipes_auto (name,type,subtype,presets,steps,core_temp,time_min,time_target,time_max) VALUES ('%s','%s','%s',%d,%d,%d,%d,%d,%d)",
  recipeSelPresets[rowpresets].name, recipeSelPresets[rowpresets].type, recipeSelPresets[rowpresets].subtype, recipeSelPresets[rowpresets].presets, recipeSelPresets[rowpresets].steps, 
  recipeSelected[rowparamts].tcore_target, recipeSelected[rowparamts].time_min, recipeSelected[rowparamts].time_target, recipeSelected[rowparamts].time_max)
  local cur = db:execute(statement)
  
  --Exctract the ID to update parameters and metadata recipe on DB
  local newcur = db:execute(string.format("SELECT id from recipes_auto WHERE name='%s' AND type='%s' AND subtype='%s'",recipeSelPresets[rowpresets].name,recipeSelPresets[rowpresets].type,recipeSelPresets[rowpresets].subtype))
  local row = newcur:fetch ({}, "a") 
  for i=1, rowpresets-1 do
    local stateUpdate = string.format("UPDATE recipes_auto SET p%d_name='%s', p%d_value=%d WHERE id=%d;",i,recipeSelPresets[i].name,i,recipeSelPresets[i].value, row.id)
    local update = db:execute(stateUpdate)
  end
    for i=1, rowparamts-1 do
    local stateUpdate = string.format("UPDATE recipes_auto SET s%d_mode='%s', s%d_humidity=%d, s%d_tempmin=%d, s%d_tempmax=%d, s%d_time=%d, s%d_speed=%d WHERE id=%d;",
    i,recipeSelected[i].mode,i,recipeSelected[i].humidity,i,recipeSelected[i].tempmin,i,recipeSelected[i].tempmax,i,recipeSelected[i].time,i,recipeSelected[i].speed,row.id)
    local update = db:execute(stateUpdate)
  end
end




local function SaveManualRecipe()
  local data = {}
  local rowparamts = table.maxn(createRecipe)
  data["name"] = gre.get_value(SAVE_NEW_RECIPE)
  data["type"] = "Manual"
  data["steps"] = rowparamts
  table.insert(createRecipe,data)
  local statement = string.format("INSERT INTO recipes_manual (name,type,steps) VALUES ('%s','%s',%d)",createRecipe[rowparamts+1].name,createRecipe[rowparamts+1].type,createRecipe[rowparamts+1].steps)
  local cur = db:execute(statement)
  
  --Exctract the ID to update parameters and metadata recipe on DB
  local newcur = db:execute(string.format("SELECT id FROM recipes_manual WHERE name='%s' ",createRecipe[rowparamts+1].name))
  local row = newcur:fetch ({}, "a")
  for i=1, rowparamts do
    local stateUpdate = string.format("UPDATE recipes_manual SET s%d_mode='%s', s%d_humidity=%d, s%d_tempmax=%d, s%d_time=%d, s%d_speed=%d WHERE id=%d;",
    i,createRecipe[i].mode,i,createRecipe[i].humidity,i,createRecipe[i].tempmax,i,createRecipe[i].time,i,createRecipe[i].speed,row.id)
    local update = db:execute(stateUpdate)
  end
  
  for i=1, table.maxn(createRecipe) do
    createRecipe[i] = nil
  end
  
  if(gToggleCreateState ~= nil )then
      gToggleCreateState = {}
  end
  nowIndxRecipe   = 1
  prevIndxRecipe  = 1
  getUserAction   = nil
  typeRecipe      = nil
  encoder_options = {}
  gre.set_value("screen_target", "Modo_Programacion")
  gre.send_event("change_screen")
  CBLoadListAllRecipes()
end



local function SaveMultilevelRecipe()
  local data = {}
  local rowparamts = table.maxn(createRecipe)
  data["name"] = gre.get_value(SAVE_NEW_RECIPE)
  data["type"] = 'Multilevel'
  data["subtype"] = getUserSubType
  
  table.insert(createRecipe,data)
  local statement = string.format("INSERT INTO recipes_multilevel (name,type,subtype) VALUES ('%s','%s','%s')",createRecipe[rowparamts+1].name,createRecipe[rowparamts+1].type,createRecipe[rowparamts+1].subtype)
  local cur = db:execute(statement)
  
  --Exctract the ID to update parameters and metadata recipe on DB
  local newcur = db:execute(string.format("SELECT id FROM recipes_multilevel WHERE name='%s' ",createRecipe[rowparamts+1].name))
  local row = newcur:fetch ({}, "a")
    
  local stateUpdate = string.format("UPDATE recipes_multilevel SET s%d_mode='%s', s%d_humidity=%d, s%d_tempmax=%d, s%d_time=%d, s%d_speed=%d WHERE id=%d;",
  1,createRecipe[1].mode,1,createRecipe[1].humidity,1,createRecipe[1].tempmax,1,createRecipe[1].time,1,createRecipe[1].speed,row.id)
  local update = db:execute(stateUpdate)
  
  for i=1, table.maxn(createRecipe) do
    createRecipe[i] = nil
  end
  
  if(gToggleCreateState ~= nil )then
      gToggleCreateState = nil
  end
  nowIndxRecipe  = 1
  prevIndxRecipe = 1
  getUserAction = nil
  gre.set_value("screen_target", "Modo_Programacion")
  gre.send_event("change_screen")
  CBLoadListAllRecipes()
end


--- Store Recipes on Database by main type ML, Auto, Manual
function CBSaveNewRecipe(mapargs)
    if(mapargs.context_screen == "Ajustes_Modo_Auto" ) then
      SaveAutomaticRecipe(mapargs)      
    elseif(mapargs.context_screen == "Crear_Receta_Manual" and typeRecipe == 'Manual') then
      SaveManualRecipe()
    elseif(mapargs.context_screen == "Crear_Receta_Manual" and typeRecipe == 'Multilevel') then
      SaveMultilevelRecipe()
    end
end


--[[  +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ]]--
--[[  +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ]]--
--[[  ****************************   START PROGRAM        **************************]]--
--[[  +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ]]--
--[[  +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ]]--
--- Start Program 
--- Load Recipe from Modo_Automatico/Intelligent on Main-screen selected
function CBLoadRecipe(mapargs)
  --gre.set_value("Layer_AutoTemplate.01_bkg_AutoRecipe.image" ,"images/17_bkg_AutoHigh.png" )
  --Wait(1000)
  --gre.set_value("Layer_AutoTemplate.01_bkg_AutoRecipe.image" ,"images/17_bkg_Auto.png" )
  
  local get_type = gre.get_value(mapargs.context_control..".recipe_type")
  recipe_id = gre.get_value(mapargs.context_control..".recipe_id")  --Change from local to global variable
  --add to test
  print("recipe_id:", recipe_id)
  print("get_type:", get_type)
  
  --- Manual Mode 
  if(get_type == "Manual") then
     SwitchRecipe_Manual(recipe_id)
     CBDisplayRecipeSteps_Manual()   
  --- intelligent Mode   
  else 
     SwitchRecipe(recipe_id)
     CBDisplayRecipeSteps_Intelligent()
     local data = {}
     data["Layer_ListTable.RecipesListTable.img."..gPreviousIndex..".1"] = 'images/bar_list_recipes.png'
     gre.set_data(data)
  end
  CBSendRecipeStep()
  gre.set_value("Layer_SettingsBar.bkg_Back.PreviousScreen", mapargs.context_screen)
  --gre.set_value("Layer_AutoTemplate.01_bkg_AutoRecipe.image" ,"images/17_bkg_Auto.png" )
end



--- When user press Play button on Modo_Programacion get full data recipe from recipe_id variable
function CBPressRun(mapargs)
   local get_type = gre.get_value(mapargs.context_control..".recipe_type")
   recipe_id = gre.get_value(mapargs.context_control..".recipe_id")
   if(get_type == 'Multilevel')then
     gre.set_value("screen_target", "Modo_MultiNivel")
     gre.send_event("change_screen")
     CBLoadMLRecipes()  
   else
     if(get_type == "Manual") then
        SwitchRecipe_Manual(recipe_id)
        CBDisplayRecipeSteps_Manual()   
     else 
        SwitchRecipe(recipe_id)
        CBDisplayRecipeSteps_Intelligent()
        local data = {}
        data["Layer_ListTable.RecipesListTable.img."..gPreviousIndex..".1"] = 'images/bar_list_recipes.png'
        gre.set_data(data)
     end
     CBSendRecipeStep()
     gre.set_value("Layer_SettingsBar.bkg_Back.PreviousScreen", mapargs.context_screen)
     gCombiOvenState = RUN_AUTO_STATE
     previousState = RUN_AUTO_STATE
     ClearBlinkTimer()
     SetBlinkTimer()
     gre.send_event ("toggle_automatic", gBackendChannel)
   end
end



function CBDeletePress(mapargs) 
  --print("heloo")
    --local data = {}
    --data["DeleteContactLayer.DeleteName.text"] = gAddressBook[gIndex].first_name.." "..gAddressBook[gIndex].last_name
    --gre.set_data(data)
    --gre.send_event("DELETE_SCREEN")
end


--[[  +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ]]--
--[[  +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ]]--
--[[ ********************SCREEN MODO_PROGRAMACION ACTIVATED*************************]]--
--[[  +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ]]--
--[[  +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ]]--

function FindRecipe(key_value)
  for i=1, table.maxn(recipes_auto) do
    local data = {}
    if( string.find(recipes_auto[i].name,key_value) ~= nil) then
       data["name"] = recipes_auto[i].name
       data["id"]   = recipes_auto[i].id
       data["type"] = recipes_auto[i].type 
       data["subtype"] = recipes_auto[i].subtype 
       table.insert(dataFilter,data)
       gFilterActived = 1
    end
  end
  
  local data = {}
  data["rows"] = table.maxn(dataFilter) 
  if ( data["rows"] ~= 0) then
     for i=1, table.maxn(dataFilter) do
       data["Layer_ListTable.RecipesListTable.txt."..i..".1"] = dataFilter[i].name --.." "..recipes_auto[i].type
       data["Layer_ListTable.RecipesListTable.img."..i..".1"] = 'images/bar_list_recipes.png'
        
        if(recipes_auto[i].type == "Intelligent") then
          if(dataFilter[i].subtype == "Aves") then
            data["Layer_ListTable.RecipesListTable.type."..i..".1"] = "images/recipe_shots/icon_AvesSmall.png"
          elseif(dataFilter[i].subtype == "Carne") then
            data["Layer_ListTable.RecipesListTable.type."..i..".1"] = "images/recipe_shots/icon_CarneSmall.png"  
          elseif(dataFilter[i].subtype == "Guarniciones") then
            data["Layer_ListTable.RecipesListTable.type."..i..".1"] = "images/recipe_shots/icon_GuarniSmall.png"   
          elseif(dataFilter[i].subtype == "Huevo") then
            data["Layer_ListTable.RecipesListTable.type."..i..".1"] = "images/recipe_shots/icon_HuevoSmall.png"  
          elseif(dataFilter[i].subtype == "Panaderia") then
            data["Layer_ListTable.RecipesListTable.type."..i..".1"] = "images/recipe_shots/icon_PanaderiaSmall.png" 
          elseif(dataFilter[i].subtype == "Pescado") then
            data["Layer_ListTable.RecipesListTable.type."..i..".1"] = "images/recipe_shots/icon_PescadoSmall.png"  
          elseif(dataFilter[i].subtype == "Reheat") then
            data["Layer_ListTable.RecipesListTable.type."..i..".1"] = "images/recipe_shots/icon_ReheatSmall.png"
          elseif(dataFilter[i].subtype == "Grill") then
            data["Layer_ListTable.RecipesListTable.type."..i..".1"] = "images/recipe_shots/icon_GrillSmall.png"           
          end
          
        elseif (recipes_auto[i].type == "Manual") then
          data["Layer_ListTable.RecipesListTable.type."..i..".1"] = "images/recipe_shots/icon_combi_small.png"        
        elseif (recipes_auto[i].type == "Multilevel") then
          data["Layer_ListTable.RecipesListTable.type."..i..".1"] = "images/recipe_shots/icon_MLSmall.png"
        end   
     end
  else 
       data["hidden"] = 1 
  end
  gre.set_data(data)
  gre.set_table_attrs("Layer_ListTable.RecipesListTable", data)
end



--- When the user selects a recipe from the list it prepare recipe options
function CBRecipePress(mapargs) 
    local data = {}
    if (mapargs.context_screen == "Modo_Programacion") then
       -- the row that was pressed in the table
        gIndex = mapargs.context_row
        --print(gIndex)
        --gre.send_event("CONTACT_SCREEN")
        data["Layer_ListTable.RecipesListTable.img."..gPreviousIndex..".1"] = 'images/bar_list_recipes.png'
        data["Layer_ListTable.RecipesListTable.img."..gIndex..".1"] = 'images/bar_list_highlight.png'
        data["Layer_EditRecipeOptions.icon_Edit.recipe_id"]   = recipes_auto[gIndex].id
        data["Layer_EditRecipeOptions.icon_Edit.recipe_type"] = recipes_auto[gIndex].type
        data["Layer_EditRecipeOptions.icon_Play.recipe_id"]   = recipes_auto[gIndex].id
        data["Layer_EditRecipeOptions.icon_Play.recipe_type"] = recipes_auto[gIndex].type
        gre.set_data(data)
        gPreviousIndex = gIndex
    end  
end



--- Recipe remove by user from Modo_Programacion screen
function CBRecipeRemove(mapargs)
    local data = {}
    local cur
    
    --Check kind of Recipe: Intelligent, Manual or ML and then remove from database
    if (gFilterActived == 1 ) then
      if(dataFilter[gIndex].type == 'Intelligent') then
        cur= db:execute(string.format("DELETE from recipes_auto WHERE id=%d", dataFilter[gIndex].id))
      elseif(dataFilter[gIndex].type == 'Manual') then
        cur= db:execute(string.format("DELETE from recipes_manual WHERE id=%d", dataFilter[gIndex].id))
      elseif(dataFilter[gIndex].type == 'Multilevel') then
        cur= db:execute(string.format("DELETE from recipes_multilevel WHERE id=%d", dataFilter[gIndex].id))
      end
      table.remove(dataFilter, gIndex)
      
    else
      if(recipes_auto[gIndex].type == 'Intelligent') then
        cur = db:execute(string.format("DELETE from recipes_auto WHERE id=%d", recipes_auto[gIndex].id))
      elseif(recipes_auto[gIndex].type == 'Manual') then
        cur = db:execute(string.format("DELETE from recipes_manual WHERE id=%d", recipes_auto[gIndex].id))
      elseif(recipes_auto[gIndex].type == 'Multilevel') then
        cur = db:execute(string.format("DELETE from recipes_multilevel WHERE id=%d", recipes_auto[gIndex].id))   
      end
      table.remove(recipes_auto, gIndex)
    end
    CBLoadListAllRecipes(mapargs)
end


---No se usa por ahora
function CBRecipeCopy(mapargs)
    local data = {}
    if (gFilterActived == 1) then  
      local cur = db:execute(string.format("INSERT INTO recipes_auto (name,type) VALUES ('%s copia','%s')", dataFilter[gIndex].name, dataFilter[gIndex].type))
    else 
      local cur = db:execute(string.format("INSERT INTO recipes_auto (name,type) VALUES ('%s','%s')", recipes_auto[gIndex].name, recipes_auto[gIndex].type))
    end
    --table.remove(recipes_auto, gIndex)
    CBLoadListAllRecipes(mapargs)
end



--[[  +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ]]--
--[[  +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ]]--
--[[  ************* M O D O _ M U L T I L E V E L  F U N C T I O N S ***************]]--
--[[  +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ]]--
--[[  +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ ]]--

---Send steps from recipeSelected: (step1)Preheat, (step2)Load, (step3)minTimer...
--recipeSelPresets has only recipes released on grid to get order by timer and then are copied to recipeSelected
function CBSendMLRecipeStep()
  local typeStep    = 0
  
  if(gindexStep == 1 and gCombiOvenState ~= RUN_MULTILEVEL_STATE)then
      typeStep  = 1
      local data = {}
      data["mode"] = "load"
      data["steam"] = 0
      data["temp"]  = 0
      data["time"]  = 0
      data["speed"] = 0
      table.insert(recipeSelected,data)
      data = {}
      
      totalSteps = table.maxn(recipeSelected)
      CBUpdateRecipeInfo(totalSteps,gindexStep,typeStep)
      Wait(2)
      gre.send_event("mode_"..recipeSelected[gindexStep].mode, gBackendChannel)
      Wait(2)
      CBUpdateSteam(recipeSelected[gindexStep].steam)
      Wait(2)
      CBUpdateTemperature(recipeSelected[gindexStep].temp)
      Wait(2)
      CBUpdateFanSpeed(recipeSelected[gindexStep].speed)
      Wait(2)
      --Toggle Oven State to Multilevel
      gCombiOvenState = RUN_MULTILEVEL_STATE
      previousState = RUN_MULTILEVEL_STATE
      gre.send_event ("toggle_multilevel", gBackendChannel)
      data = {}
      data["hidden"] = 0
      gre.set_group_attrs("Layer_Pop_ups.icon_preheat_ML",data)  --Set Window discharge level msg    
      
  elseif(gindexStep == 2)then
      local data = {}
      typeStep = 0
      CBUpdateRecipeInfo(totalSteps,gindexStep,typeStep)
      Wait(2)
      gre.send_event("mode_"..recipeSelected[gindexStep].mode, gBackendChannel)
      data = {}
      data["hidden"] = 1
      gre.set_group_attrs("Layer_Pop_ups.icon_preheat_ML",data)  --Set Window discharge level msg    
      
  
  elseif(gindexStep > 2)then
      ClearDischargeMsg()
      CBUpdateTime(recipeSelected[gindexStep].time, 0)
      typeStep  = 2
      totalSteps = table.maxn(recipeSelected)
      --print("stps:"..totalSteps)
      Wait(2)
      CBUpdateRecipeInfo(totalSteps,gindexStep,typeStep)
      Wait(2)
      gre.send_event("mode_"..recipeSelected[gindexStep].mode, gBackendChannel)
      gCombiOvenMode = recipeSelected[gindexStep].mode
      Wait(2)
      CBUpdateSteam(recipeSelected[gindexStep].steam)
      Wait(2)
      CBUpdateTemperature(recipeSelected[gindexStep].temp)
      Wait(2)
      CBUpdateFanSpeed(recipeSelected[gindexStep].speed)
      Wait(2)
  end
end



function CBAddNewMLRecipe()
  FindRecipe('ML ')
end




function CBClearMLCart()
  local data = {}
  for i=1, 7 do
    --data[string.format("Layer_MultiLevel.Data_Level_%d.icon.img",i)] = nil 
    data[string.format("Layer_MultiLevel.Data_Level_%d.text_name.data",i)] = " "
    data[string.format("Layer_MultiLevel.Data_Level_%d.text_time.data",i)] = " "  
    data[string.format("Layer_MultiLevel.Data_Level_%d.bar_progress.percent",i)] = -405
  end
  data["Layer_MultiLevel.icon_PlayML.alpha"] = 0
  gre.set_data(data)
  gindexStep = 1
  ClearStepTable()
end





--- Load recipes from ML home shorcut
function CBLoadMLRecipes()
  CBClearMLCart()
  ClearTable()
  local statement = string.format("SELECT id,name,subtype FROM recipes_multilevel")
  local cur = db:execute(statement)
  local row = cur:fetch ({}, "a")
  -- Iterate through the results and populate the lua table
  while row do 
    local data={}
    data["name"] = row.name
    data["id"]   = row.id
    data["subtype"] = row.subtype
    table.insert(recipes_auto,data)
    --We're done with this row of data so switch with the next
    row = cur:fetch({}, "a")
  end
  table.sort(recipes_auto, function(e1, e2) return e1.name < e2.name end )
  local data={}
  --We create list on display with bkg image and icon by type 
  local colsTable  = table.maxn(recipes_auto)/2 --TotalAL_Cols = (row.name + row.id + row-type) * (table.maxn(recipes_auto))
  local count=1 --total elements count
  local max_elements=table.maxn(recipes_auto)
  
  gre.set_table_attrs("Layer_MLOptions.RecipesMLTable", {rows = max_elements})
  for i=1, 2 do
    for j=1, colsTable do
      if count <= max_elements then
        data[string.format("Layer_MLOptions.RecipesMLTable.name.%d.%d",i,j)] = recipes_auto[count].name  
        if (recipes_auto[count].subtype == "Aves") then
          data[string.format("Layer_MLOptions.RecipesMLTable.type.%d.%d",i,j)] = "images/recipe_shots/icon_AvesSmall.png"
        elseif(recipes_auto[count].subtype == "Carne") then
          data[string.format("Layer_MLOptions.RecipesMLTable.type.%d.%d",i,j)] = "images/recipe_shots/icon_CarneSmall.png"
        elseif(recipes_auto[count].subtype == "Guarniciones") then
          data[string.format("Layer_MLOptions.RecipesMLTable.type.%d.%d",i,j)] = "images/recipe_shots/icon_GuarniSmall.png"
        elseif(recipes_auto[count].subtype == "Huevo") then
          data[string.format("Layer_MLOptions.RecipesMLTable.type.%d.%d",i,j)] = "images/recipe_shots/icon_HuevoSmall.png"
        elseif(recipes_auto[count].subtype == "Panaderia") then
          data[string.format("Layer_MLOptions.RecipesMLTable.type.%d.%d",i,j)] = "images/recipe_shots/icon_PanaderiaSmall.png"
        elseif(recipes_auto[count].subtype == "Pescado") then
          data[string.format("Layer_MLOptions.RecipesMLTable.type.%d.%d",i,j)] = "images/recipe_shots/icon_PescadoSmall.png"
        elseif(recipes_auto[count].subtype == "Reheat") then
          data[string.format("Layer_MLOptions.RecipesMLTable.type.%d.%d",i,j)] = "images/recipe_shots/icon_ReheatSmall.png"
        elseif(recipes_auto[count].subtype == "Grill") then
          data[string.format("Layer_MLOptions.RecipesMLTable.type.%d.%d",i,j)] = "images/recipe_shots/icon_GrillSmall.png"
      end      
      data[string.format("Layer_MLOptions.RecipesMLTable.recipe_id.%d.%d",i,j)] = recipes_auto[count].id
      --print("i:"..count)
      count=count + 1
      
      else return
      end
    end
  end
  gre.set_data(data)  
  data = {}
  data["cols"] = colsTable
  if (data["cols"] == 0) then
      data["hidden"] = 1
   else
      data["hidden"] = 0
   end
   gre.set_table_attrs("Layer_MLOptions.RecipesMLTable", data)
  -- CBInitScroll()
end




--- Adjust bar time when user release a recipe on workspace [each level RE-ORDER AND COPY EACH ONE]
function UpdateTimeBarML(level_index)
  --MAX_BAR_PROGRESS is the maximun ORANGE BAR lenght 
  local MAX_BAR_PROGRESS = 370
  local max_index = table.maxn(recipeSelPresets)
  local data = {}
  table.sort(recipeSelPresets, function(e1, e2) return e1.time < e2.time end )
  for i=1, max_index do
    local computeXoff = (-375 + (recipeSelPresets[i].time * MAX_BAR_PROGRESS) / recipeSelPresets[max_index].time )
    data[string.format("Layer_MultiLevel.Data_Level_%d.bar_progress.percent",recipeSelPresets[i].level)] = computeXoff
    --print("x:",computeXoff)
    --data[string.format("Layer_MultiLevel.Data_Level_%d.bar_progress.percent",recipeSelPresets[i].level)] = (recipeSelPresets[i].time * MAX_BAR_PROGRESS) / recipeSelPresets[max_index].time
    recipeSelected[i+2] = recipeSelPresets[i]
  end
  gMaxTimeML = recipeSelPresets[max_index].time
  gre.set_data(data)
end



---When user makes a drop MLRecipe inside 1-7 level get a data backup to compare on next step 
function CheckPresetsML(recipe,level_index)  
  local statement = string.format("SELECT * from recipes_multilevel where id=%s",recipe)
  local cur = db:execute(statement)
  local row = cur:fetch({}, "a")
  
  local max_index = table.maxn(recipeSelPresets) 
  if (max_index >= 1 and row.s1_mode ~= recipeSelPresets[1].mode) then
     return
  end
  
  local data={}
  data["mode"]  = row.s1_mode
  data["steam"] = row.s1_humidity
  data["temp"]  = row.s1_tempmax
  data["time"]  = row.s1_time
  data["speed"] = row.s1_speed
  data["level"] = level_index
  table.insert(recipeSelPresets,data) -- almacena los datos en un array de backup de unicamente 7 elementos 
  table.insert(recipeSelected,data)   -- almacena los datos en un array agregando 2 pasos de preheat y load para ejecutar los presets 

  data = {}
  if (row.subtype == "Aves") then
    data[string.format("Layer_MultiLevel.Data_Level_%d.icon.img",level_index)] = "images/recipe_shots/icon_AvesSmall.png"
  elseif(row.subtype == "Carne") then
    data[string.format("Layer_MultiLevel.Data_Level_%d.icon.img",level_index)] = "images/recipe_shots/icon_CarneSmall.png"
  elseif(row.subtype == "Guarniciones") then
    data[string.format("Layer_MultiLevel.Data_Level_%d.icon.img",level_index)] = "images/recipe_shots/icon_GuarniSmall.png"
  elseif(row.subtype == "Huevo") then
    data[string.format("Layer_MultiLevel.Data_Level_%d.icon.img",level_index)] = "images/recipe_shots/icon_HuevoSmall.png"
  elseif(row.subtype == "Panaderia") then
    data[string.format("Layer_MultiLevel.Data_Level_%d.icon.img",level_index)] = "images/recipe_shots/icon_PanaderiaSmall.png"
  elseif(row.subtype == "Pescado") then
    data[string.format("Layer_MultiLevel.Data_Level_%d.icon.img",level_index)] = "images/recipe_shots/icon_PescadoSmall.png"
  elseif(row.subtype == "Reheat") then
    data[string.format("Layer_MultiLevel.Data_Level_%d.icon.img",level_index)] = "images/recipe_shots/icon_ReheatSmall.png"
  elseif(row.subtype == "Grill") then
    data[string.format("Layer_MultiLevel.Data_Level_%d.icon.img",level_index)] = "images/recipe_shots/icon_GrillSmall.png"
  end

  data[string.format("Layer_MultiLevel.Data_Level_%d.text_name.data",level_index)] = row.name
  data[string.format("Layer_MultiLevel.Data_Level_%d.text_time.data",level_index)] = string.format("%.2d:%.2d", row.s1_time/60, row.s1_time%60)
  gre.set_data(data)
  UpdateTimeBarML(level_index)  -- Update the time bar on each level
  CBSendMLRecipeStep()
  if(gindexStep ~= 1)then
    gre.send_event ("toggle_multilevel", gBackendChannel)
  end
end


