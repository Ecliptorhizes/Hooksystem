--[[
	HookTypes
	Purpose:
	Declare shared Luau type contracts for HookService and hook subsystem modules.
]]

export type HookData = {
	Constraint: RopeConstraint | SpringConstraint,
	BeamPart: BasePart,
	Attachments: { Attachment },
	PlayerAtt: Attachment,
	TargetAtt: Attachment,
	ArmForce: VectorForce?,
	AttachTime: number?,
}

export type PlayerHookState = {
	left: HookData?,
	right: HookData?,
	LinearVelocity: Instance?,
	VelocityAttachment: Attachment?,
	GravityForce: VectorForce?,
	GravityAttachment: Attachment?,
	LastTick: number,
	JumpBoostEndTime: number?,
	ReelEndTime: number?,
	LastBoostTime: number?,
	HeartbeatConn: RBXScriptConnection,
	RagdollPreventionConn: RBXScriptConnection?,
	RagdollPostSimConn: RBXScriptConnection?,
	LimbCollisionBackup: { { part: BasePart, canCollide: boolean } }?,
}

return {}
