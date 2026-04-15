--[[
    This script handles the client-side inventory system,
    including UI rendering, item preview, and equipment logic.

    This code is made publicly accessible exclusively for the purpose of
    evaluation in the HiddenDevs Luau Scripter role application.
    It is not intended for public reuse, distribution, or production use.

    This code is working on the following game:
    https://www.roblox.com/games/119239269226854/Punch-Warriors
]]

--// Services & Modules
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

local Knit = require(RS.packages.Knit)
local UIhandler = require(RS.modules.UIhandler)

local inventoryService

--// Utils
local player = Players.LocalPlayer
local blur = Lighting.Blur

--// UI
local hub = player.PlayerGui:WaitForChild("Hub")
local main = player.PlayerGui:WaitForChild("Main")
local invMain = hub.Inventory.Main

-- Buttons
local invBtn = main.mainButtons.inventory
local closeBtn = invMain.close
local equipBtn = invMain.preview.desc.equip

-- Preview
local preview = invMain.preview.image
local previewTitle = invMain.preview.title.TextLabel
local previewRarity = preview.rarity
local previewDesc = invMain.preview.desc.TextLabel

-- Other
local topic_accessories = invMain.topics.accessories
local topic_emotes = invMain.topics.emotes
local slots = preview.Parent.desc.slots

--// Constants
local LAST_TAB
local CONTROLLERS_CACHE = {}
local IS_UPDATING = false

--// Tweens
local invHiddenPos = invMain.Position + UDim2.fromOffset(0, 20)
local inventoryTween = TweenService:Create(
	invMain,
	TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	{ Position = invMain.Position }
)

--// Local functions
-- Render the preview of an item
local function renderItem(frame, item, stroke)

    -- Nametags
	if item.category == "nametags" then
		local textColor = Color3.fromHex(
			string.match(item.content, "#%x%x%x%x%x%x") -- Extracts the <font color> param from nametag content
				or "#FFFFFF"
		) -- Or #FFFFFF

		local darkerTxtColor = Color3.new(
			math.clamp(textColor.R * 0.5, 0, 1),
			math.clamp(textColor.G * 0.5, 0, 1),
			math.clamp(textColor.B * 0.5, 0, 1)
		) -- Darker text color for the stroke

		frame.TextLabel.Text = item.content -- Render the content of the nametag in the preview

		if stroke then
			frame.TextLabel.UIStroke.Color = darkerTxtColor
		end

		frame.TextLabel.Visible = true

    -- Emotes
	elseif item.category == "emotes" then
		-- Preparing the dummy
		local dummy = frame.ViewportFrame.WorldModel.Dummy

		local animation = frame.Animation
		local animController = dummy:FindFirstChildWhichIsA("AnimationController")
            or Instance.new("AnimationController", dummy) -- Creates the AnimationController if doesnt exists
		local animator = animController:FindFirstChildOfClass("Animator")
            or Instance.new("Animator", animController) -- Also creates the Animator if doesnt exists

		-- Stops all other animations that the dummy may be playing
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			track:Stop()
		end

		-- Loads and play the new animation
		animation.AnimationId = "rbxassetid://" .. item.animId

		local animTrack = animator:LoadAnimation(animation)
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
	if not item then
		return
	end

	-- Resetting and displaying the item in the preview
	resetPreview()

	previewTitle.Text = item.name
	previewRarity.Text = item.rarityName
	previewRarity.TextColor = BrickColor.new(item.rarityColor)
	previewDesc.Text = item.description

	renderItem(preview, item, false)

	-- Changes the equip button to "equip" or "unequip"
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
	local container = invMain.container.ScrollingFrame

	-- Preparing the template and rendering the new item
	local template = container.template:Clone()
	template.Name = item.name
	template.LayoutOrder = if isEquipped then -item.rarity else -item.rarity + 10 -- Shows equipped items on top of unequipped ones
	template.ImageColor3 = item.rarityColor
	template.Parent = container

	renderItem(template, item, true)

	-- Custom background if the item is equipped, to highlight it.
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
	if IS_UPDATING then
		return
	end
	IS_UPDATING = true -- Debounce to prevent duplicated items

	local success, result = pcall(function()
		local categoryMap = {
			accessories = { "nametags" },
			emotes = { "emotes" },
		}

		-- Get the items requested from categoryMap
		local requestedCategories = categoryMap[tab]
		if
			not requestedCategories
			or (tab == LAST_TAB and not force) -- Dont update the inventory again if the current tab is the requested one
		then
			return
		end
		LAST_TAB = tab

		-- Clear old items
		local container = invMain.container.ScrollingFrame
		for _, item in pairs(container:GetChildren()) do
			if item:IsA("ImageButton") and item.Name ~= "template" then -- Prevent deleting things that is not an item
				item:Destroy()
			end
		end

		-- Getting the player inventory
		local success, inventory = inventoryService:getInventory(requestedCategories):await()
		if not success then
			return
		end

		-- Goes through every category and displays each item
		local items = 0
		for categoryName, categoryData in pairs(inventory) do
			for _, item in pairs(categoryData.all) do
				if typeof(item) ~= "table" or not next(item) then
					continue -- Continues if the item is not valid (not a table or empty)
				end
				items += 1

				-- Checks if the item is equipped
				local isEquipped = false
				if item.category == "emotes" then
					for _, equippedEmote in pairs(categoryData.equipped) do -- Goes through every equipped emote
						if equippedEmote[item.id] then
							isEquipped = true
							break
						end
					end
				elseif item.category == "nametags" then
					if categoryData.equipped[item.id] then -- Just sees if the current equipped nametag is the one that will be displayed
						isEquipped = true
					end
				end

				createItem(item, isEquipped)
			end
		end

		container.Parent.TextLabel.Visible = items == 0 -- Shows a text if the inventory is empty
	end)

	if not success then
		warn(result)
	end
	IS_UPDATING = false
end

-- Hides all others UIs
local function hideHub()
	for _, ui in pairs(hub:GetChildren()) do
		if -- Sees if the ui is valid and visible. If not, continue.
			not ui:IsA("Folder")
			or not ui:FindFirstChild("Main")
			or not ui.Main:IsA("ImageLabel")
			or not ui.Main.Visible
		then
			continue
		end

		local controllerName = ui.Main:GetAttribute("controller") -- Getting the controller for the ui

		if CONTROLLERS_CACHE[controllerName] then
			CONTROLLERS_CACHE[controllerName]:toggleUI() -- This will hide the ui, since this will only be executed if its visible.
		else
			-- Caching the controller to not require it every time
			local controller = Knit.GetController(controllerName)
			CONTROLLERS_CACHE[controllerName] = controller
			controller:toggleUI()
		end
	end
end

--// Global functions
local inventoryController = Knit.CreateController({
	Name = "inventoryController",
})

-- Toggle inventory UI
function inventoryController:toggleUI()
	if not invMain.Visible then -- Showing the inventory
		hideHub()

		invMain.Position = invHiddenPos
		invMain.Visible = true
		hub.background.BackgroundColor3 = Color3.fromRGB(43, 33, 10)
		hub.background.Visible = true
		blur.Size = 20

		inventoryTween:Play()
		updateInv("accessories")

	else -- Hidding the inventory
		invMain.Visible = false
		hub.background.Visible = false
		blur.Size = 0
	end
end

-- Main
function inventoryController:KnitStart()
	inventoryService = Knit.GetService("inventoryService")

	-- Setup UI handlers
	local invBtnHandler = UIhandler.new(invBtn, {
		Pc = Enum.KeyCode.E,
		Xbox = Enum.KeyCode.ButtonY,
	})
	local topic_accessoriesHandler = UIhandler.new(topic_accessories, { Pc = Enum.KeyCode.One })
	local topic_emotesHandler = UIhandler.new(topic_emotes, { Pc = Enum.KeyCode.Two })

	local equipBtnHandler = UIhandler.new(equipBtn)
	local closeBtnHandler = UIhandler.new(closeBtn)

	-- Handle each button when clicked
	invBtnHandler.Clicked = function()
		inventoryController:toggleUI()
	end
	topic_accessoriesHandler.Clicked = function()
		updateInv("accessories")
	end
	topic_emotesHandler.Clicked = function()
		updateInv("emotes")
	end
	closeBtnHandler.Clicked = function()
		inventoryController:toggleUI()
	end

	equipBtnHandler.Clicked = function()
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
	for _, slot in pairs(slots.slotsFrame:GetChildren()) do
		if not slot:IsA("GuiObject") then
			continue
		end
		local slotHandler = UIhandler.new(slot)

		slotHandler.Clicked = function()
			local item = HttpService:JSONDecode(equipBtn:GetAttribute("item")) -- Getting item data

			local success, result = inventoryService:equipItem(item.category, item.id, slot.Name):await() -- Requesting the equip

			-- Changes the equip button to "unequip" if the item has been equipped successfully.
			if success and result == true then
				equipBtn.ImageColor3 = Color3.new(0.862745, 0.152941, 0.152941)
				equipBtn.TextLabel.Text = "unequip"
				equipBtn.TextLabel.UIStroke.Color = Color3.new(0.596078, 0.105882, 0.105882)
				updateInv(item.tab, true)
			end

			slots.Visible = false
		end
	end
end

return inventoryController
