--[[
    Inventory Controller
    This script handles the client-side inventory system,
    including UI rendering, item preview, and equipment logic.

    This code is made publicly accessible exclusively for the purpose of
    evaluation in the HiddenDevs Luau Scripter role application.
    It is not intended for public reuse, distribution, or production use.

    This code is working on the following game:
    https://www.roblox.com/games/119239269226854/Punch-Warriors
]]

--// Services & Modules
local Lighting = game:GetService("Lighting")
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Knit = require(RS.packages.Knit)
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local UIhandler = require(RS.modules.UIhandler)

local inventoryService

--// Utils
local Player = Players.LocalPlayer
local Hub = Player.PlayerGui:WaitForChild("Hub")
local Blur = Lighting.Blur
local Main = Hub.Inventory.Main

--// UI
local closeBtn = Main.close
local equipBtn = Main.preview.desc.equip

local preview = Main.preview.image
local previewTitle = Main.preview.title.TextLabel
local previewRarity = preview.rarity
local previewDesc = Main.preview.desc.TextLabel

local topic_accessories = Main.topics.accessories
local topic_emotes = Main.topics.emotes
local slots = preview.Parent.desc.slots

--// Constants
local lastTab
local controllersCache = {}
local isUpdating = false

--// Tweens
local invHiddenPos = Main.Position + UDim2.fromOffset(0, 20)
local inventoryTween = TweenService:Create(
	Main,
	TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	{Position = Main.Position}
)

--// Local functions
-- Render the preview of an item
local function renderItem(frame, item, stroke)
	if item.category == "nametags" then
		local textColor = Color3.fromHex(string.match(item.content, "#%x%x%x%x%x%x") or "#FFFFFF") -- Extracts the <font color> param from nametag content
		local darkerTxtColor = Color3.new(
			math.clamp(textColor.R * 0.5, 0, 1),
			math.clamp(textColor.G * 0.5, 0, 1),
			math.clamp(textColor.B * 0.5, 0, 1)
		) -- Darker text color for the stroke

		frame.TextLabel.Text = item.content
		if stroke then frame.TextLabel.UIStroke.Color = darkerTxtColor end
		frame.TextLabel.Visible = true

	elseif item.category == "emotes" then
        -- Preparing the dummy
		local Dummy = frame.ViewportFrame.WorldModel.Dummy
		local Animation = frame.Animation
		local animController = Dummy:FindFirstChildWhichIsA("AnimationController") or Instance.new("AnimationController", Dummy)
		local Animator = animController:FindFirstChildOfClass("Animator") or Instance.new("Animator", animController)

        -- Stops all other animations that the dummy may be playing
		for _, track in ipairs(Animator:GetPlayingAnimationTracks()) do
			track:Stop()
		end

        -- Loads and play the new animation
		Animation.AnimationId = "rbxassetid://"..item.animId
		local animTrack = Animator:LoadAnimation(Animation)
		animTrack.Looped = true
		animTrack:Play()
		frame.ViewportFrame.Visible = true
	end
end

-- Prepares the preview to display another item later
local function resetPreview()
	preview.ViewportFrame.Visible = false
	preview.ImageLabel.Visible = false
	preview.TextLabel.Visible = false
end

-- Handles when the player clicks an item
local function handleItemClick(item, equipped: boolean)
	if not item then return end

    -- Resetting and displaying the item in the preview
	resetPreview()
	previewTitle.Text = item.name
	previewRarity.Text = item.rarityName
	previewRarity.TextColor = BrickColor.new(item.rarityColor)
	previewDesc.Text = item.description
	renderItem(preview, item, false)

	-- Equip button handling
	local equipBtn = equipBtn.properties.Object
	if not equipped then
		equipBtn.ImageColor3 = Color3.new(0.262745, 0.768627, 0.380392)
		equipBtn.TextLabel.Text = "equip"
		equipBtn.TextLabel.UIStroke.Color = Color3.new(0.180392, 0.529412, 0.262745)
	else
		equipBtn.ImageColor3 = Color3.new(0.862745, 0.152941, 0.152941)
		equipBtn.TextLabel.Text = "unequip"
		equipBtn.TextLabel.UIStroke.Color = Color3.new(0.596078, 0.105882, 0.105882)
	end
	equipBtn.Visible = true

	local encodedItem = HttpService:JSONEncode(item)
	equipBtn:SetAttribute("item", encodedItem) -- Will be used when the player clicks the equip button
end

-- Creates a new item in the item list
local function createItem(item, isEquipped)
	local container = Main.container.ScrollingFrame

    -- Preparing the template and rendering the new item
	local template = container.template:Clone()
	template.Name = item.name
    template.LayoutOrder = isEquipped and -item.rarity or (-item.rarity + 10)
    template.ImageColor3 = item.rarityColor
    template.Parent = container
	renderItem(template, item, true) -- Rendering the item

    -- Custom background if the item is equipped, to highlight him.
	if isEquipped then
		template.Image = "rbxassetid://125538611128658"
	end
    template.Visible = true

    -- Handles when the item is clicked
	local button = UIhandler.new(template)
	button.Clicked = function()
		handleItemClick(item, isEquipped)
	end
end

-- Updates the inventory
local function updateInv(tab, force)
	if isUpdating then return end
	isUpdating = true -- Debounce to prevent duplicated items

	local success, result = pcall(function()
		local categoryMap = {
			accessories = { "nametags" },
			emotes = { "emotes" }
		}

        -- Get the items requested from categoryMap
		local requestedCategories = categoryMap[tab]
		if not requestedCategories then return end

        -- Dont update the inventory again if the current tab is the requested one
		if tab == lastTab and not force then return end
		lastTab = tab

        -- Clear old items
		local Container = Main.container.ScrollingFrame
		for _,v in pairs(Container:GetChildren()) do
			if v:IsA("ImageButton") and v.Name ~= "template" then v:Destroy() end
		end

        -- Getting the player inventory
		local success, inventory = inventoryService:getInventory(requestedCategories):await()
		if not success then return end

		local items = 0 -- Counting to know if there is atleast one item in inventory
		for categoryName, categoryData in pairs(inventory) do
			for _,item in pairs(categoryData.all) do
				if typeof(item) ~= "table" or next(item) == nil then continue end -- Return if the item is not valid (not a table or empty table)
				items += 1

                -- Checks if the item is equipped
				local isEquipped = false
				if item.category == "emotes" then
					for _, equippedEmote in pairs(categoryData.equipped) do -- Go through every equipped emote
						if equippedEmote[item.id] then
							isEquipped = true
							break
						end
					end

				elseif item.category == "nametags" then
					if categoryData.equipped[item.id] then -- Just checking if the nametag is equipped or not
						isEquipped = true
					end
				end

				createItem(item, isEquipped) -- Finally, creating the item (showing it in inventory)
			end
		end

		Container.Parent.TextLabel.Visible = items == 0 -- Shows a text if the inventory is empty
	end)

	if not success then warn(result) end
	isUpdating = false
end

-- Hides all others UIs
local function hideHub()
	for _,ui in pairs(Hub:GetChildren()) do
		if not ui:IsA("Folder") then continue end
		if not ui:FindFirstChild("Main") or not ui.Main:IsA("ImageLabel") then continue end
		if not ui.Main.Visible then continue end

		local controllerName = ui.Main:GetAttribute("controller") -- Getting the controller for the UI

		if controllersCache[controllerName] then
			controllersCache[controllerName]:toggleUI()
		else
            -- Caching the controller to not require it every time
			local controller = Knit.GetController(controllerName)
			controllersCache[controllerName] = controller
			controller:toggleUI()
		end
	end
end

--// Global functions
local inventoryController = Knit.CreateController {
	Name = "inventoryController"
}

-- Toggle inventory UI
function inventoryController:toggleUI()
	if not Main.Visible then
		hideHub()

        -- Showing the inventory, background and blur
		Main.Position = invHiddenPos
		Main.Visible = true
		Hub.background.BackgroundColor3 = Color3.fromRGB(43, 33, 10)
		Hub.background.Visible = true
		Blur.Size = 20

		inventoryTween:Play() -- Inventory opening animation
		updateInv("accessories")
	else
        -- Hides the inventory, background and blur
		Main.Visible = false
		Hub.background.Visible = false
		Blur.Size = 0
	end
end

-- Main
function inventoryController:KnitStart()
	inventoryService = Knit.GetService("inventoryService")

    local invBtn = Player.PlayerGui:WaitForChild("Main").mainButtons.inventory

    -- Setup UI handlers
    invBtn = UIhandler.new(invBtn, { Pc = Enum.KeyCode.E, Xbox = Enum.KeyCode.ButtonY })
	topic_accessories = UIhandler.new(topic_accessories, { Pc = Enum.KeyCode.One })
	topic_emotes = UIhandler.new(topic_emotes, { Pc = Enum.KeyCode.Two })

	equipBtn = UIhandler.new(equipBtn)
	closeBtn = UIhandler.new(closeBtn)

    -- Handle each button when clicked
    invBtn.Clicked = function()
		inventoryController:toggleUI()
	end
	topic_accessories.Clicked = function()
		updateInv("accessories")
	end
	topic_emotes.Clicked = function()
		updateInv("emotes")
	end
	closeBtn.Clicked = function()
		inventoryController:toggleUI()
	end

	equipBtn.Clicked = function()
		local equipBtn = equipBtn.properties.Object
		local item = HttpService:JSONDecode(equipBtn:GetAttribute("item"))

        -- Equip the item
        if equipBtn.TextLabel.Text == "equip" then
            if not item.selectSlot then
                local success, result = inventoryService:equipItem(item.category, item.id):await() -- Requesting the equip

                if success and result then -- Only continues if the item has been equipped successfully
                    equipBtn.ImageColor3 = Color3.new(0.862745, 0.152941, 0.152941)
                    equipBtn.TextLabel.Text = "unequip"
                    equipBtn.TextLabel.UIStroke.Color = Color3.new(0.596078, 0.105882, 0.105882)
                    updateInv(item.tab, true)
                end

            else
                slots.Visible = true
            end

        -- Unequip the item
        elseif equipBtn.TextLabel.Text == "unequip" then
            local success, result = inventoryService:unequipItem(item.category, item.id):await() -- Requesting the unequip

            if success and result then -- Only continues if the item has been unequipped successfully
                equipBtn.ImageColor3 = Color3.new(0.262745, 0.768627, 0.380392)
                equipBtn.TextLabel.Text = "equip"
                equipBtn.TextLabel.UIStroke.Color = Color3.new(0.180392, 0.529412, 0.262745)
                updateInv(item.tab, true)
            end
        end
	end

    -- Setup slot buttons
	for _,slot in pairs(slots.slotsFrame:GetChildren()) do
		if not slot:IsA("GuiObject") then continue end
		slot = UIhandler.new(slot)

        -- Handle when clicked
		slot.Clicked = function()
			local equipBtn = equipBtn.properties.Object
			local item = HttpService:JSONDecode(equipBtn:GetAttribute("item")) -- Getting item data

            local success, result = inventoryService:equipItem(item.category, item.id, slot.properties.Object.Name):await() -- Requesting the equip

            -- Changes the equip button if the item has been equipped successfully.
            if success and result == true then
                equipBtn.ImageColor3 = Color3.new(0.862745, 0.152941, 0.152941)
                equipBtn.TextLabel.Text = "unequip"
                equipBtn.TextLabel.UIStroke.Color = Color3.new(0.596078, 0.105882, 0.105882)
                updateInv(item.tab, true)
            end

			slots.Visible = false -- Hides the slots
		end
	end
end

return inventoryController
