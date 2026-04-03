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

-- Services & Modules
local Lighting = game:GetService("Lighting")
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Knit = require(RS.packages.Knit)
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local inventoryService

local UIhandler = require(RS.modules.UIhandler)

-- Utils
local Player = Players.LocalPlayer
local Hub = Player.PlayerGui:WaitForChild("Hub")
local Blur = Lighting.Blur
local Main = Hub.Inventory.Main

local closeBtn = Main.close
local equipBtn = Main.preview.desc.equip

local preview = Main.preview.image
local previewTitle = Main.preview.title.TextLabel
local previewRarity = preview.rarity
local previewDesc = Main.preview.desc.TextLabel

local topic_acessories = Main.topics.acessories
local topic_emotes = Main.topics.emotes
local slots = preview.Parent.desc.slots

local lastTab

-- Constants
local controllersCache = {}
local db = false

-- Main
local inventoryController = Knit.CreateController {
	Name = "inventoryController"
}

-- Tweens
local invHiddenPos = Main.Position + UDim2.fromOffset(0, 20)
local inventoryTween = TweenService:Create(
	Main,
	TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	{Position = Main.Position}
)

-- Loads the preview of the item
local function renderItem(frame, item, stroke)
	if item.category == "nametags" then
		local textColor = Color3.fromHex(string.match(item.content, "#%x%x%x%x%x%x") or "#FFFFFF")
		local darkerColor = Color3.new(
			math.clamp(textColor.R * 0.5, 0, 1),
			math.clamp(textColor.G * 0.5, 0, 1),
			math.clamp(textColor.B * 0.5, 0, 1)
		)

		frame.TextLabel.Text = item.content
		if stroke then frame.TextLabel.UIStroke.Color = darkerColor end
		frame.TextLabel.Visible = true

	elseif item.category == "emotes" then
		local Dummy = frame.ViewportFrame.WorldModel.Dummy
		local Animation = frame.Animation
		local animController = Dummy:FindFirstChildWhichIsA("AnimationController") or Instance.new("AnimationController", Dummy)
		local Animator = animController:FindFirstChildOfClass("Animator") or Instance.new("Animator", animController)

		for _, track in ipairs(Animator:GetPlayingAnimationTracks()) do
			track:Stop()
		end

		Animation.AnimationId = "rbxassetid://"..item.animId
		local animTrack = Animator:LoadAnimation(Animation)
		animTrack.Looped = true
		animTrack:Play()
		frame.ViewportFrame.Visible = true
	end
end

-- Resets the preview
local function resetPreview()
	preview.ViewportFrame.Visible = false
	preview.ImageLabel.Visible = false
	preview.TextLabel.Visible = false
end

-- Setup each an item in inventory
local function onItemClicked(item, equipped)
	if not item then return end

	-- Preview
	resetPreview()

	previewTitle.Text = item.name
	previewRarity.Text = item.rarityName
	previewRarity.TextColor = BrickColor.new(item.rarityColor)
	previewDesc.Text = item.description

	renderItem(preview, item, false)

	-- Equip button
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
	equipBtn:SetAttribute("item", encodedItem)
end

-- Creates a new item in the inventory UI
local function createItem(item, equipped)
	local Container = Main.container.ScrollingFrame

	local template = Container.template
	template = template:Clone()
	template.Name = item.name
	template.Parent = Container

	if equipped then
		template.LayoutOrder = -item.rarity
	else
		template.LayoutOrder = -item.rarity + 10
	end

	template.ImageColor3 = item.rarityColor

	renderItem(template, item, true)

	if equipped then
		template.Image = "rbxassetid://125538611128658"
	end
	template.Visible = true

	local button = UIhandler.new(template)
	button.Clicked = function()
		onItemClicked(item, equipped)
	end
end

-- Updates the inventory items
local function updateInv(tab, force)
	if db then return end
	db = true

	local success, result = pcall(function()
		local allowedCategories = {
			acessories = { "nametags" },
			emotes = { "emotes" }
		}

		local requestedCategories = allowedCategories[tab]
		if not requestedCategories then return end

		if tab == lastTab and not force then return end
		lastTab = tab

		local Container = Main.container.ScrollingFrame

		for _,v in pairs(Container:GetChildren()) do
			if v:IsA("ImageButton") and v.Name ~= "template" then v:Destroy() end
		end

		local success, inventory = inventoryService:getInventory(requestedCategories):await()
		if not success then return end

		local items = 0
		for categoryName, categoryData in pairs(inventory) do
			for _,item in pairs(categoryData.all) do
				if typeof(item) ~= "table" or next(item) == nil then continue end
				items += 1
				local isEquipped = false

				if item.category == "emotes" then
					for _, equippedEmote in pairs(categoryData.equipped) do
						if equippedEmote[item.id] then
							isEquipped = true
							break
						end
					end
				elseif item.category == "nametags" then
					if categoryData.equipped[item.id] then
						isEquipped = true
					end
				end

				createItem(item, isEquipped)
			end
		end

		Container.Parent.TextLabel.Visible = items == 0
	end)

	if not success then warn(result) end

	db = false
end

-- Hides all others UIs
local function hideHub()
	for _,v in pairs(Hub:GetChildren()) do
		if not v:IsA("Folder") then continue end
		if not v:FindFirstChild("Main") or not v.Main:IsA("ImageLabel") then continue end
		if not v.Main.Visible then continue end

		local controllerName = v.Main:GetAttribute("controller")

		if controllersCache[controllerName] then
			controllersCache[controllerName]:toggleUI()
		else
			local controller = Knit.GetController(controllerName)
			controllersCache[controllerName] = controller
			controller:toggleUI()
		end
	end
end

-- Hides inventory UI
function inventoryController:toggleUI()
	if not Main.Visible then
		hideHub()

		Main.Position = invHiddenPos
		Main.Visible = true
		Hub.background.BackgroundColor3 = Color3.fromRGB(43, 33, 10)
		Hub.background.Visible = true

		Blur.Size = 20
		inventoryTween:Play()
		updateInv("acessories")
	else
		Main.Visible = false
		Hub.background.Visible = false
		Blur.Size = 0
	end
end

-- Main
function inventoryController:KnitStart()
	inventoryService = Knit.GetService("inventoryService")

    local invBtn = Player.PlayerGui:WaitForChild("Main").mainButtons.inventory
    invBtn = UIhandler.new(invBtn, {
        Pc = Enum.KeyCode.E,
        Xbox = Enum.KeyCode.ButtonY
    })

	topic_acessories = UIhandler.new(topic_acessories, {
		Pc = Enum.KeyCode.One
	})

	topic_emotes = UIhandler.new(topic_emotes, {
		Pc = Enum.KeyCode.Two
	})

	local equipBtn = UIhandler.new(equipBtn)

	closeBtn = UIhandler.new(closeBtn)

    invBtn.Clicked = function()
		inventoryController:toggleUI()
	end

	topic_acessories.Clicked = function()
		updateInv("acessories")
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

			if equipBtn.TextLabel.Text == "equip" then

				if not item.selectSlot then
					local success, result = inventoryService:equipItem(item.category, item.id):await()
					if success and result then
						equipBtn.ImageColor3 = Color3.new(0.862745, 0.152941, 0.152941)
						equipBtn.TextLabel.Text = "unequip"
						equipBtn.TextLabel.UIStroke.Color = Color3.new(0.596078, 0.105882, 0.105882)
						updateInv(item.tab, true)
					end
				
				else
					slots.Visible = true
				end

			else

					local success, result = inventoryService:unequipItem(item.category, item.id):await()
					if success and result then
						equipBtn.ImageColor3 = Color3.new(0.262745, 0.768627, 0.380392)
						equipBtn.TextLabel.Text = "equip"
						equipBtn.TextLabel.UIStroke.Color = Color3.new(0.180392, 0.529412, 0.262745)
						updateInv(item.tab, true)
					end

			end

	end

	for _,v in pairs(slots.slotsFrame:GetChildren()) do
		if not v:IsA("GuiObject") then continue end
		local v = UIhandler.new(v)
		v.Clicked = function()

			local equipBtn = equipBtn.properties.Object
			local item = HttpService:JSONDecode(equipBtn:GetAttribute("item"))

			if equipBtn.TextLabel.Text == "equip" then
				local success, result = inventoryService:equipItem(item.category, item.id, v.properties.Object.Name):await()
				if success == true and result == true then
					equipBtn.ImageColor3 = Color3.new(0.862745, 0.152941, 0.152941)
					equipBtn.TextLabel.Text = "unequip"
					equipBtn.TextLabel.UIStroke.Color = Color3.new(0.596078, 0.105882, 0.105882)
					updateInv(item.tab, true)
				end

			end

			slots.Visible = false
		end
	end
end

return inventoryController
