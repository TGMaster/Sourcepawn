#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4downtown>
#include <smlib>

// Define
#define DEBUG
#define INFECTED_TEAM 3
#define ZC_TANK 8
#define PLUGIN_AUTHOR "Breezy"
#define PLUGIN_VERSION "1.0"

// Bhop
#define BoostForward 60.0

// Velocity
enum VelocityOverride {
	VelocityOvr_None = 0,
	VelocityOvr_Velocity,
	VelocityOvr_OnlyWhenNegative,
	VelocityOvr_InvertReuseVelocity
};

public Plugin:myinfo = 
{
	name = "AI: Tank Behaviour",
	author = PLUGIN_AUTHOR,
	description = "Blocks AI tanks from throwing rocks",
	version = PLUGIN_VERSION,
	url = ""
};

/*
===================================================================================
=                           	   TANK BHOP                                      =
===================================================================================
*/
public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon, &subtype, &cmdnum, &tickcount, &seed, mouse[2]) {
	//Proceed if this player is a tank
	if(IsBotTank(client)) {
		new tank = client;
		new flags = GetEntityFlags(tank);
		
		// Get the player velocity:
		new float:fVelocity[3];
		GetEntPropVector(client, Prop_Data, "m_vecVelocity", fVelocity);
		new float:currentspeed = SquareRoot(Pow(fVelocity[0],2.0)+Pow(fVelocity[1],2.0));
		//PrintCenterTextAll("Tank Speed: %.1f", currentspeed);
		
		// Get Angle of Tank
		decl Float:clientEyeAngles[3];
		GetClientEyeAngles(tank,clientEyeAngles);
		
		// Start fast pouncing if close enough to survivors
		new iSurvivorsProximity = GetSurvivorProximity(tank);
		new bool:bHasSight = bool:GetEntProp(tank, Prop_Send, "m_hasVisibleThreats"); //Line of sight to survivors
		
		// Near survivors
		if (bHasSight && (450 > iSurvivorsProximity > 100) && currentspeed > 190.0) // Random number to make bhop?
		{
			buttons &= ~IN_ATTACK2;			// Block throwing rock
			if (flags & FL_ONGROUND) {
				buttons |= IN_DUCK;
				buttons |= IN_JUMP;
				if(buttons & IN_FORWARD)
					Client_Push(client,clientEyeAngles,BoostForward,VelocityOverride:{VelocityOvr_None,VelocityOvr_None,VelocityOvr_None});
						
				if(buttons & IN_BACK){
					clientEyeAngles[1] += 180.0;
					Client_Push(client,clientEyeAngles,BoostForward,VelocityOverride:{VelocityOvr_None,VelocityOvr_None,VelocityOvr_None});
				}
						
				if(buttons & IN_MOVELEFT){
					clientEyeAngles[1] += 90.0;
					Client_Push(client,clientEyeAngles,BoostForward,VelocityOverride:{VelocityOvr_None,VelocityOvr_None,VelocityOvr_None});
				}
						
				if(buttons & IN_MOVERIGHT){
					clientEyeAngles[1] += -90.0;
					Client_Push(client,clientEyeAngles,BoostForward,VelocityOverride:{VelocityOvr_None,VelocityOvr_None,VelocityOvr_None});
				}
			}
			//Block Jumping and Crouching when on ladder
			if (GetEntityMoveType(tank) & MOVETYPE_LADDER) {
				buttons &= ~IN_JUMP;
				buttons &= ~IN_DUCK;
			}
		}
	}
	return Plugin_Changed;
}

public Action:L4D2_OnSelectTankAttack(client, &sequence)
{
	if (IsFakeClient(client) && sequence == 50)
	{
		sequence = GetRandomInt(0, 1) ? 49 : 51;
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

bool:IsBotTank(client) {
	// Check the input is valid
	if (!IsValidClient(client)) return false;
	// Check if player is on the infected team, a hunter, and a bot
	if (GetClientTeam(client) == INFECTED_TEAM) {
		new zombieClass = GetEntProp(client, Prop_Send, "m_zombieClass");
		if (zombieClass == ZC_TANK) {
			if(IsFakeClient(client)) { // is a bot
				return true;
			}
		}
	}
	return false; // otherwise
}

bool:IsValidClient(client) {
    if ( !( 1 <= client <= MaxClients ) || !IsClientInGame(client) ) return false;      
    return true; 
}

bool:IsSurvivor(client)
{
	return (client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2);
}

GetSurvivorProximity(referenceClient) {
	// Get the reference's position
	new Float:referencePosition[3];
	GetEntPropVector(referenceClient, Prop_Send, "m_vecOrigin", referencePosition);
	// Find the proximity of the closest survivor
	new iClosestAbsDisplacement = -1; // closest absolute displacement
	for (new client = 1; client < MaxClients; client++) {
		if (IsValidClient(client) && IsSurvivor(client)) {
			// Get displacement between this survivor and the reference
			new Float:survivorPosition[3];
			GetEntPropVector(client, Prop_Send, "m_vecOrigin", survivorPosition);
			new iAbsDisplacement = RoundToNearest(GetVectorDistance(referencePosition, survivorPosition));
			// Start with the absolute displacement to the first survivor found:
			if (iClosestAbsDisplacement == -1) {
				iClosestAbsDisplacement = iAbsDisplacement;
			} else if (iAbsDisplacement < iClosestAbsDisplacement) { // closest survivor so far
				iClosestAbsDisplacement = iAbsDisplacement;
			}			
		}
	}
	// return the closest survivor's proximity
	return iClosestAbsDisplacement;
}


// Thanks Chanz (Infinite Jumping plugin)
stock Client_Push(client, Float:clientEyeAngle[3], Float:power, VelocityOverride:override[3]=VelocityOvr_None)
{
	decl Float:forwardVector[3],
	Float:newVel[3];
	
	GetAngleVectors(clientEyeAngle, forwardVector, NULL_VECTOR, NULL_VECTOR);
	NormalizeVector(forwardVector, forwardVector);
	ScaleVector(forwardVector, power);
	//PrintToChatAll("Tank velocity: %.2f", forwardVector[1]);
	
	Entity_GetAbsVelocity(client,newVel);
	
	for(new i=0;i<3;i++){
		switch(override[i]){
			case VelocityOvr_Velocity:{
				newVel[i] = 0.0;
			}
			case VelocityOvr_OnlyWhenNegative:{				
				if(newVel[i] < 0.0){
					newVel[i] = 0.0;
				}
			}
			case VelocityOvr_InvertReuseVelocity:{				
				if(newVel[i] < 0.0){
					newVel[i] *= -1.0;
				}
			}
		}
		
		newVel[i] += forwardVector[i];
	}
	
	Entity_SetAbsVelocity(client,newVel);
}